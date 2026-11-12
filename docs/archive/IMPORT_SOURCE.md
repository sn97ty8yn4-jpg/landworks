# One-time source import

The GitHub Actions workflow is installed. The project itself must still be copied into this Git repository before actual Godot execution can begin.

## Recommended: GitHub Desktop

1. Download **Landworks_v0.6_GitHub_Ready.zip** from the ChatGPT conversation and extract it.
2. In GitHub Desktop, clone **sn97ty8yn4-jpg/landworks**.
3. Open the cloned repository directory.
4. Copy the **contents** of the extracted ZIP into this directory; not an outer folder. You should see **project.godot** directly alongside README.md. Preserve the cloned repository's hidden **.git** directory.
5. In GitHub Desktop, commit the changes to main, then select **Push origin**.
6. Visit https://github.com/sn97ty8yn4-jpg/landworks/actions.

Alternatively, the ZIP contains **tools/windows/PUBLISH_TO_GITHUB_WINDOWS.bat**, a helper for a Windows PC with a working Git installation and GitHub authentication. It clones the repo to Documents\\landworks-github, copies the source, commits and pushes it. It does not store personal access tokens.

## CI acceptance

- Runs the Godot 4.6.1 editor in headless mode, detects script and import errors.
- Runs Python source checks separately.
- Runs seven actual physics scenarios via tools/run_work_tests.py, with real CSV outputs.
- Rejects missing or incomplete measurement files.
- Publishes Godot logs and recorded CSVs as artifacts.

A failed initial run due to **missing project.godot** is expected until source import completes. An offline structural pass is **not** evidence that machinery physics works.
