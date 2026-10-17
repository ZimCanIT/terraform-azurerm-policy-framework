import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]


snapshot_discovery_failures = []

# The module set is the state set: each module owns the resources of one state,
# so the principal that applies a state needs only that state's permissions.
# catalogue and behaviour-resolution are provider-free and own no resource.
module_names = {
    "catalogue",
    "behaviour-resolution",
    "content",
    "identity-rbac",
    "assignments",
    "operations",
}

scope_families = ("management_group", "subscription", "resource_group", "resource")

# Every AzureRM resource type has exactly one owning module. Identities and role
# assignments exist only in identity-rbac and policy assignments only in
# assignments, so neither the assignment state nor the operations state can
# grant itself a role.
resource_owners = {
    "content": {
        "azurerm_policy_definition",
        "azurerm_policy_set_definition",
        "azurerm_management_group_policy_set_definition",
    },
    "identity-rbac": {"azurerm_user_assigned_identity", "azurerm_role_assignment"},
    "assignments": {f"azurerm_{scope}_policy_assignment" for scope in scope_families},
    "operations": {
        f"azurerm_{scope}_policy_{kind}"
        for scope in scope_families
        for kind in ("remediation", "exemption")
    },
}

# Modules that create Azure resources document the permissions their state needs
# and the separation it relies on.
permission_headings = ("## Azure permissions", "## Separation of duties")


def git_paths(*arguments):
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return set(result.stdout.splitlines())


def tracked_files():
    listed = git_paths("ls-files", "--cached", "--others", "--exclude-standard")
    deleted = git_paths("ls-files", "--deleted")

    # Removed placeholder directories are intentionally absent from this
    # worktree. Keep other missing tracked files visible as a snapshot error.
    unexpected_deletions = sorted(
        path for path in deleted if Path(path).name != ".gitkeep"
    )
    snapshot_discovery_failures.extend(
        f"tracked file is unexpectedly missing from the public snapshot: {path}"
        for path in unexpected_deletions
    )

    candidates = listed - deleted
    for path in sorted(candidates):
        if not (root / path).is_file():
            snapshot_discovery_failures.append(
                f"candidate file is missing from the worktree and not reported by git as deleted: {path}"
            )
    return [root / line for line in sorted(candidates)]


def manifest_files(manifest):
    paths = json.loads(manifest.read_text(encoding="utf-8-sig"))
    if not isinstance(paths, list) or any(not isinstance(path, str) for path in paths):
        raise ValueError("public snapshot manifest must be a list of relative file paths")
    files = []
    for path in sorted(set(paths)):
        candidate = root / path
        if Path(path).is_absolute() or root not in candidate.resolve().parents:
            raise ValueError(f"public snapshot manifest path escapes the snapshot: {path}")
        if not candidate.is_file():
            snapshot_discovery_failures.append(f"public snapshot manifest file is missing: {path}")
            continue
        files.append(candidate)
    return files


def public_markdown(files):
    return [
        path
        for path in files
        if path.suffix.lower() == ".md" and "docs" not in path.relative_to(root).parts
    ]


def check_links(markdown_files, candidate_files):
    failures = []
    public_paths = {path.resolve() for path in candidate_files}
    pattern = re.compile(r"(?<!!)]\(\s*([^\s)]+)(?:\s+[^)]*)?\s*\)")
    for path in markdown_files:
        text = path.read_text(encoding="utf-8")
        if re.search(r"\]\(\s*(?:\.\./)?docs(?:/|\\)", text, re.IGNORECASE):
            failures.append(f"{path.relative_to(root)} links to ignored docs/")
        for target in pattern.findall(text):
            if re.match(r"(?i)(?:[a-z][a-z0-9+.-]*:|//|#)", target):
                continue
            target_path, _, _ = target.partition("#")
            resolved = (path.parent / target_path).resolve()
            # Directory links are valid only when that directory contains a
            # candidate public file. Worktree existence alone is insufficient.
            published = resolved in public_paths or any(
                resolved in candidate.parents for candidate in public_paths
            )
            if not published or root not in resolved.parents:
                failures.append(f"{path.relative_to(root)} has missing local link: {target}")
    return failures


def check_package_snapshot(files):
    failures = []
    local_parts = {"docs", ".git", ".terraform", "__pycache__"}
    local_names = {"agents.md", ".terraform.lock.hcl", ".terraformrc", "terraform.rc"}
    local_suffixes = {".tfstate", ".tfstate.backup", ".tfplan", ".plan", ".pyc", ".tfvars", ".tfvars.json"}
    snapshot = []
    for path in files:
        relative = path.relative_to(root)
        parts = {part.lower() for part in relative.parts}
        name = relative.name.lower()
        if parts & {part.lower() for part in local_parts}:
            failures.append(f"local-only path is in the public snapshot: {relative}")
            continue
        if name in local_names or name.endswith(tuple(local_suffixes)):
            failures.append(f"local-only artefact is in the public snapshot: {relative}")
            continue
        if not path.is_file():
            failures.append(f"snapshot entry is not a file: {relative}")
            continue
        snapshot.append((relative.as_posix(), path.read_bytes()))

    required = {"README.md", "LICENSE", "main.tf", "variables.tf", "outputs.tf", "versions.tf"}
    present = {name for name, _ in snapshot}
    for name in sorted(required - present):
        failures.append(f"public source snapshot is missing required file: {name}")

    digest = hashlib.sha256()
    for name, content in sorted(snapshot):
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(hashlib.sha256(content).digest())
        digest.update(b"\n")
    print(f"public source snapshot: {len(snapshot)} files, SHA256 {digest.hexdigest()}")
    return failures


def check_forbidden_operations(files):
    failures = []
    pattern = re.compile(r"(?i)\b(terraform\s+(?:apply|destroy)|az\s+(?:deployment|policy)|registry.*publish)\b")
    for path in files:
        if ".github" not in path.relative_to(root).parts:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if any(
            pattern.search(line)
            and not re.match(r"^\s*!\s*grep\s+-RniE\b", line)
            for line in text.splitlines()
        ):
            failures.append(f"forbidden operation configured in {path.relative_to(root)}")
    return failures


def check_module_set(files):
    present = set()
    for path in files:
        parts = path.relative_to(root).parts
        if len(parts) > 2 and parts[0] == "modules":
            present.add(parts[1])
    failures = [f"modules/{name} is missing from the module set" for name in sorted(module_names - present)]
    failures.extend(
        f"modules/{name} is not part of the module set" for name in sorted(present - module_names)
    )
    return failures


def check_resource_ownership(files):
    declaration = re.compile(r'^\s*resource\s+"(azurerm_[a-z0-9_]+)"\s+"[^"]+"', re.MULTILINE)
    declared = {}
    for path in files:
        parts = path.relative_to(root).parts
        if path.suffix != ".tf":
            continue
        # Examples, tests and fixtures consume modules and may declare their own
        # resources. Only the root module and the top level of each module count.
        if len(parts) == 1:
            owner = "the root module"
        elif len(parts) == 3 and parts[0] == "modules":
            owner = parts[1]
        else:
            continue
        text = path.read_text(encoding="utf-8")
        for match in declaration.finditer(text):
            declared.setdefault(match.group(1), set()).add(owner)

    failures = []
    for resource_type, owners in sorted(declared.items()):
        if len(owners) > 1:
            failures.append(
                f"{resource_type} is declared in several modules: {', '.join(sorted(owners))}"
            )
        for owner in sorted(owners):
            if resource_type not in resource_owners.get(owner, set()):
                failures.append(
                    f"{owner} declares {resource_type}, which the ownership map does not assign to it"
                )
    for owner, resource_types in sorted(resource_owners.items()):
        for resource_type in sorted(resource_types):
            if owner not in declared.get(resource_type, set()):
                failures.append(f"the ownership map assigns {resource_type} to {owner}, which does not declare it")
    return failures


def check_permission_sections(files):
    failures = []
    readmes = {path.relative_to(root).as_posix(): path for path in files}
    for module in sorted(resource_owners):
        name = f"modules/{module}/README.md"
        if name not in readmes:
            failures.append(f"{name} is missing")
            continue
        headings = set()
        in_fence = False
        for line in readmes[name].read_text(encoding="utf-8").splitlines():
            if line.startswith("```"):
                in_fence = not in_fence
            elif not in_fence and line.startswith("## "):
                headings.add(line.rstrip())
        failures.extend(
            f"{name} is missing the '{heading}' section"
            for heading in permission_headings
            if heading not in headings
        )
    return failures


# Secret scanning is owned by the gitleaks step in .github/workflows/security.yml.
parser = argparse.ArgumentParser(description="Check the exact public source candidate inventory.")
parser.add_argument("--manifest", type=Path, help="Use a JSON file inventory for an isolated package snapshot.")
arguments = parser.parse_args()
files = manifest_files(arguments.manifest) if arguments.manifest else tracked_files()
failures = list(snapshot_discovery_failures)
failures.extend(check_links(public_markdown(files), files))
failures.extend(check_package_snapshot(files))
failures.extend(check_forbidden_operations(files))
failures.extend(check_module_set(files))
failures.extend(check_resource_ownership(files))
failures.extend(check_permission_sections(files))
if failures:
    print("\n".join(failures))
    sys.exit(1)
print("repository publication and documentation gates passed")
