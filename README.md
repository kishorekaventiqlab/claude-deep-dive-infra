# claude-deep-dive-infra

> **Warning.** This repository deliberately creates **misconfigured** AWS resources: an S3 bucket without a
> bucket-level public access block, a security group open to SSH from anywhere, an unencrypted EBS volume and an IAM
> policy that allows everything. They exist to be found by a security scanner in an isolated sandbox account for the
> AventiqLab teaching series *Claude Deep Dive*. **Do not apply this code to any other AWS account.**

## What is here

- `bootstrap/`: the sandbox's one-time foundation (roles, GitHub OIDC trust, state bucket, budget), applied by hand.
  The read-only investigation role, and separate least-privilege roles for planning, deploying and tearing down.
- `bootstrap/guardrails/`, `bootstrap/scp-region-lock.json`: the guardrail on the sandbox administrator user and the
  Organization policy that keeps the sandbox in one region.
- `demo/` and `.github/workflows/` (added later): the demo resources, applied and destroyed only by GitHub Actions.
- `scripts/`: the tests that prove the roles and guardrails do what they claim.

## How it is kept safe

- The sandbox is a dedicated AWS account with no production resources and no trust to other accounts.
- Nothing deployed is reachable: no instances can be launched, no volume attached, no bucket made public, no policy
  attached. Every demo resource is destroyed automatically each night.
- GitHub Actions reach AWS only through OIDC; no AWS key is stored anywhere in this repository or its settings.
- Changes reach `main` only through pull requests whose checks pass.

Not affiliated with or sponsored by Amazon Web Services or Anthropic.
