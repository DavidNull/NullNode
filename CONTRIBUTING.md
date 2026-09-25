# Contributing to NullNode

Thanks for your interest in contributing to NullNode! This project is a personal LLMOps lab, but contributions are welcome.

## How to Contribute

### Report Bugs

Before reporting a bug, search if a similar issue already exists. If not, create a new issue with:

- **Title:** Brief description of the problem
- **Description:** Details of expected vs actual behavior
- **Steps to reproduce:** Specific steps to recreate the problem
- **Environment:** OS, Docker/k3d/Helm/Terraform versions
- **Logs:** Relevant output from `make status`, `make smoke`, or specific logs

### Suggest Improvements

For new features or improvements:

- **Title:** Brief description of the improvement
- **Description:** Explain the improvement and why it would be useful
- **Alternatives:** Mention alternative solutions you've considered
- **Impact:** How it would affect the existing architecture

### Pull Requests

1. **Fork** the repository
2. Create a **branch** for your feature/fix (`feature/your-name`)
3. **Commit** your changes with clear messages
4. **Push** to your branch
5. Create a **Pull Request** describing your changes

### Code Standards

- Follow existing patterns in the project
- Use **Helm** for k8s changes
- Use **Terraform** for infrastructure changes
- **Validate** your changes with `make validate` before committing
- **Document** relevant changes in README or docs/

### Testing

Before sending a PR:

```bash
make validate    # helm, terraform, scripts validation
make smoke      # end-to-end test if you have the cluster running
```

## Review Process

PRs will be reviewed with attention to:

- **Functionality:** Does the change work as expected?
- **Architecture:** Does it align with existing patterns?
- **Documentation:** Is it appropriately documented?
- **Testing:** Does it include validation?

## Communication Style

- Be respectful and constructive
- Accept feedback positively
- Explain your reasoning clearly
- Ask if something isn't clear

## License

By contributing, you agree that your contributions are published under the same license as the project.

## Contact

For general questions, open an issue with the `question` label.

---

**Note:** This is a personal learning project. Contributions are handled in free time, so please be patient with reviews.
