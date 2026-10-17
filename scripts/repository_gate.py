import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]


snapshot_discovery_failures = []


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


# Secret scanning is owned by the gitleaks step in .github/workflows/security.yml.
parser = argparse.ArgumentParser(description="Check the exact public source candidate inventory.")
parser.add_argument("--manifest", type=Path, help="Use a JSON file inventory for an isolated package snapshot.")
arguments = parser.parse_args()
files = manifest_files(arguments.manifest) if arguments.manifest else tracked_files()
failures = list(snapshot_discovery_failures)
failures.extend(check_links(public_markdown(files), files))
failures.extend(check_package_snapshot(files))
failures.extend(check_forbidden_operations(files))
if failures:
    print("\n".join(failures))
    sys.exit(1)
print("repository publication and documentation gates passed")
