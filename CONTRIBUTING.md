# Contributing to Egress

Thanks for helping improve Egress. Bug reports, documentation fixes, tests,
and focused feature proposals are welcome.

## Before opening an issue

- Search existing issues and discussions first.
- Do not include AWS credentials, private keys, Terraform state, generated
  client profiles, QR codes, public server addresses, or bootstrap logs that
  may contain sensitive deployment details.
- Use the security process in [SECURITY.md](SECURITY.md) for vulnerabilities.
- For feature requests, explain the use case and the operational or security
  tradeoffs. Please open an issue before undertaking a large change.

## Development setup

The supported local workflow uses Bash, Terraform 1.6 or newer, ShellCheck,
`jq`, and Make. `qrencode` and the AWS CLI are needed for live deployments but
not for the test suite.

On macOS:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform shellcheck jq make
```

On Ubuntu or Debian, install ShellCheck, `jq`, and Make with the system package
manager, then install Terraform from HashiCorp's official package repository.

Run the complete local check before submitting a change:

```bash
make check
```

This checks Bash syntax, runs ShellCheck, verifies Terraform formatting and
validation, executes the local tests, and dry-runs the operational Make
targets. It initializes Terraform without a backend and does not create AWS
resources or require AWS credentials.

## Pull requests

- Keep changes focused and document user-visible behavior.
- Add or update tests when behavior changes.
- Format Terraform with `terraform -chdir=terraform fmt`.
- Keep shell scripts compatible with the Bash version shipped by current
  macOS releases unless a compatibility change is discussed first.
- Never make deployment or integration tests spend money automatically.
- Confirm that `make check` passes and that no secret or generated file is in
  the diff.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
Contributions are licensed under the repository's [MIT License](LICENSE).
