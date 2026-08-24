# Security policy

## Supported versions

Security fixes are made on the `main` branch. This project does not currently
publish versioned releases or maintain older branches.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Report it
privately through [GitHub's private vulnerability reporting
form](https://github.com/Yanis897349/egress/security/advisories/new). Include:

- the affected file, revision, or workflow;
- the impact and conditions required to reproduce it;
- minimal reproduction steps or a proof of concept; and
- any suggested remediation, if available.

Do not include real credentials, client profiles, private keys, Terraform
state, or an active server address. Use redacted or disposable test data.

If private vulnerability reporting is unavailable, contact the maintainer
through their [GitHub profile](https://github.com/Yanis897349) and ask for a
private reporting channel without disclosing vulnerability details.

## Operational scope

Egress provisions internet-facing infrastructure. Operators are responsible
for protecting AWS and SSH credentials, reviewing Terraform plans, restricting
administrative access where practical, applying upstream security updates, and
destroying unused resources. The project cannot provide security support for
client software, AWS, Xray-core, or sing-box; upstream vulnerabilities should
also be reported to the relevant project.
