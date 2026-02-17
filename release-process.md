# GitHub Release Process Documentation

## Overview
This document outlines the automated release process for deploying code to devnet environments using GitHub Actions.

## Prerequisites
- Repository must have the GitHub Actions workflow file: auto-release.yml
- User must have permissions to create Pull Requests and labels
- Repository must have a `main` branch and a `release` branch

## Step-by-Step Release Process

### Step 1: Prepare Release Branch
1. Ensure your code changes are ready for deployment
2. Create or update the `release` branch with the latest changes
3. Push the `release` branch to the repository

### Step 2: Create Pull Request
1. Create a Pull Request from `release` branch to `main` branch
2. Add a descriptive title and description for the release

### Step 3: Add Required Labels
Add the following **mandatory** labels to your Pull Request:

#### Required Labels:
- **`release`** - Triggers the release workflow
- **Version label** - Format: `0.2.0`
  - Examples: `1.2.3`, `2.0.1`
- **Devnet label** - Format: `devnetX` where X is a number
  - Examples: `devnet0`, `devnet1`, `devnet2`

#### Example Label Combination:
```
✅ release
✅ 1.2.0
✅ devnet1
```

### Step 4: Review and Merge
1. Review the Pull Request changes
2. Ensure all checks pass
3. **Merge** the Pull Request (do not just close it)

### Step 5: Automated Process Execution
Once merged, the GitHub Actions workflow will automatically:

1. **Validate Labels** - Check that all required labels are present
2. **Check Version Tag** - Ensure the version tag doesn't already exist
3. **Delete Existing Resources** - Remove devnet tag and GitHub release if devnet tag is being repeated
4. **Create/Update Devnet Branch** - Create or update the devnet branch (e.g., `devnet1`)
5. **Generate Changelog** - Create release notes with commit history
6. **Create Git Tags** - Create both version tag (e.g., `v1.2.0`) and devnet tag (e.g., `Devnet1`)
7. **Create GitHub Release** - Publish release with changelog

## What Gets Created

### Branches
- **Devnet Branch**: `devnet1` (lowercase) - Contains deployed code
- **Main Branch**: Updated with merged changes

### Tags
- **Version Tag**: `v1.2.0` - Semantic version tag
- **Devnet Tag**: `Devnet1` (capitalized) - Deployment environment tag

### GitHub Release
- **Name**: `Release v1.2.0 - Devnet1`
- **Tag**: `Devnet1`
- **Notes**: Includes changelog with commit history
- **Status**: Prerelease (for devnet deployments)

## Naming Conventions

| Type | Format | Example | Purpose |
|------|--------|---------|---------|
| PR Labels | `devnetX` | `devnet1` | Specifies target environment |
| Git Branches | `devnetX` | `devnet1` | Long-lived deployment branch |
| Git Tags | `DevnetX` | `Devnet1` | Deployment milestone marker |
| Version Tags | `vX.Y.Z` | `v1.2.0` | Semantic version marker |

## Error Scenarios

### Missing Labels
```
❌ Missing required labels: version label (e.g., 1.0.0) and devnet label (devnet0, devnet1, devnet2, etc.)
```
**Solution**: Add the missing labels to your PR

### Duplicate Version Tag
```
❌ Version tag v1.2.0 already exists. Please use a new version.
```
**Solution**: Use a different version number (e.g., `1.2.1`)

### Wrong PR Source
```
Workflow only runs for PRs from 'release' branch to 'main' branch
```
**Solution**: Ensure your PR is from `release` → `main`

## Changelog Generation

The workflow automatically generates a changelog by:
1. Finding the last devnet tag for the same environment
2. Comparing commits between the last tag and current HEAD
3. Including commit messages with short hashes
4. Limiting to 20 commits if no previous tag exists

## Best Practices

1. **Use Devnet Semantic Versioning**: Follow `0.X.Y` format where:
   - **0** = Always 0 for devnet releases
   - **X** = Devnet number (matches devnet label, e.g., 1 for devnet1, 2 for devnet2)
   - **Y** = Release increment for that devnet (starts from 0)
   
   Examples:
   - First release to devnet1: `0.1.0`
   - Second release to devnet1: `0.1.1`
   - Third release to devnet1: `0.1.2`
   - First release to devnet2: `0.2.0`


2. **Descriptive Commit Messages**: Will appear in changelog
3. **Test Before Release**: Ensure code is tested before merging
4. **Incremental Versions**: Don't skip version numbers within the same devnet
5. **Environment Isolation**: Use different devnet numbers for different features

### Version Examples by Devnet

| Devnet | Version Sequence | Description |
|--------|------------------|-------------|
| devnet1 | `0.1.0`, `0.1.1`, `0.1.2` | Feature branch A releases |
| devnet2 | `0.2.0`, `0.2.1`, `0.2.2` | Feature branch B releases |
| devnet3 | `0.3.0`, `0.3.1`, `0.3.2` | Integration testing releases |

## Monitoring

After triggering the release:
1. Check the **Actions** tab for workflow progress
2. Monitor for any error messages in the workflow logs
3. Verify the created branch, tags, and release
4. Confirm deployment to the target devnet environment

## Support

For issues with the release process:
1. Check workflow logs in GitHub Actions
2. Verify all prerequisites are met
3. Ensure proper permissions are granted
4. Review error messages for specific guidance