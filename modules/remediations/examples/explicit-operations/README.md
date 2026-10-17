# Remediations synthetic example

This provider-free-contract example demonstrates bounded, filtered caller-supplied discovery. Discovery is non-mutating and does not query Azure. Change `mode` to `execute` only with an explicit approval reference, role scope, resource limit and eligible resolved assignment context.

Terraform state and outputs record intent and resource identity, not Azure compliance or remediation success.
