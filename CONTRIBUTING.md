# Contributing Guidelines

Thank you for your interest in contributing to our project! We welcome all contributions. To ensure a smooth and collaborative process, we have established a set of guidelines that we ask all contributors to follow.

## Code of Conduct

All participants are expected to follow our [Code of Conduct](CODE_OF_CONDUCT.md). Please make sure you are familiar with its contents.

## How to Contribute

Our workflow is designed to be straightforward and efficient, centered around the GitHub issue tracker and pull requests.

1. **Find or Create an Issue**: Before you start working, navigate to the [Issues tab](https://github.com/Flexksx/distributed_applications_labs/issues) of our repository.
    * Look for an existing issue that you want to work on.
    * If no issue exists for the task you have in mind, please create a new one. Provide a clear title and a detailed description of the feature or bug.
2. **Assign the Issue**: Assign the issue to yourself to let the team know you are working on it. If you cannot assign it yourself, leave a comment asking to be assigned.
3. **Create a Branch**: Create a new branch from the `main` branch to work on your assigned issue.
4. **Develop**: Make your changes in the branch. Commit your work in small, logical steps with clear messages.
5. **Submit a Pull Request**: Once your work is complete, push your branch to the repository and open a Pull Request against the `main` branch.

## Branching Standard

This project revolves around trunk-based development. The `main` branch is the single source of truth. All feature development and bug fixes are done in short-lived branches created from `main`.

## Pull Request (PR) Process

Pull Requests are the core of our contribution process. We aim for PRs to be small, focused units of work that solve a specific problem without disrupting the development flow.

### PR Content

Your Pull Request description is essential for reviewers. Please fill out the PR template completely, ensuring it includes the following:

1. **Link to the Issue**: The PR description must link to the issue it resolves using a keyword like `Closes #<issue-number>`. This automatically links the PR to the issue and closes the issue when the PR is merged.
2. **Summary of Changes**: Briefly describe the changes you made and the problem you solved.
3. **Testing**: Detail the testing you have performed to verify your changes.

### Review and Merging

* **Reviewers**: Please request a review from at least one other team member.
* **Approvals Required**: A PR must receive at least **one approval** before it can be merged.
* **Merging Strategy**: We use the **Squash and merge** strategy. This keeps our `main` branch history clean and linear, with each commit corresponding to a single merged PR. The person merging the PR should ensure the commit message is clean and references the original issue number.

## Commit Message Guidelines

While not strictly enforced, we encourage following the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. This helps in creating an explicit and readable commit history.

A commit message should be structured as follows:

```
<type>: <subject>

[optional body]
```

**Common types:**

* **feat**: A new feature
* **fix**: A bug fix
* **docs**: Documentation only changes
* **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc.)
* **refactor**: A code change that neither fixes a bug nor adds a feature
* **test**: Adding missing tests or correcting existing tests

**Example:** `feat: Implement user registration endpoint`

Since squashing will result in a single commit, you can edit the final message to this convention.

Thank you for contributing!
