# Landworks — publish the real project to GitHub

**Preferred method: GitHub Desktop**

1. Extract this ZIP to a folder, for example `C:\Projects\Landworks-v0.6`.
2. Open GitHub Desktop; **File > Clone repository**, select `sn97ty8yn4-jpg/landworks`.
3. Open the cloned repository folder in Windows Explorer.
4. Copy **everything inside the extracted Landworks-v0.6 folder** into that repository folder (including `.github`, `landworks`, `tools`, `docs`, `tests` and `project.godot`). Do not copy the outer folder itself. Do not delete `.git` from the cloned folder.
5. In GitHub Desktop, **Commit to main**, then **Push origin**.
6. Open https://github.com/sn97ty8yn4-jpg/landworks/actions to inspect the Godot import and field-trial run.

**Command-line alternative**: if Git for Windows is installed and authenticated, double-click `tools/windows/PUBLISH_TO_GITHUB_WINDOWS.bat` from this extracted folder. It clones into `Documents\landworks-github`, copies the source and pushes; it never asks you to send GitHub credentials to ChatGPT.

**Note**: earlier offline calculations are *not* confirmed gameplay results. The CI job must run the actual Godot scenes, produce all seven CSV scenarios and archive the outputs. When the run fails, share the GitHub Actions run link so the logs can be inspected and corrected.
