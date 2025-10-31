# CodeArtifact Migration Script

A bash script to migrate npm packages between AWS CodeArtifact repositories.

## Overview

This script copies all npm packages and their versions from a source CodeArtifact repository to a target CodeArtifact repository. It handles authentication, downloads packages, and republishes them to the destination.

## Prerequisites

- AWS CLI installed and configured
- `jq` command-line JSON processor
- `npm` installed
- Appropriate AWS permissions for both source and target repositories

## Configuration

Before running the script, update the configuration variables at the top of `migration.sh`:

```bash
# Source repository
SOURCE_DOMAIN="your-source-domain"
SOURCE_REPO="your-source-repo"
SOURCE_PROFILE="your-aws-profile"
SOURCE_ACCOUNT_ID="123456789012"

# Target repository
TARGET_DOMAIN="your-target-domain"
TARGET_REPO="your-target-repo"
TARGET_PROFILE="your-aws-profile"
TARGET_ACCOUNT_ID="123456789012"
```

## Usage

1. Make the script executable:
   ```bash
   chmod +x migration.sh
   ```

2. Run the migration:
   ```bash
   ./migration.sh
   ```

## What it does

1. **Lists packages** from the source repository
2. **Gets authorization tokens** for both repositories
3. **Downloads each package version** from source
4. **Publishes to target repository**
5. **Skips existing packages** to avoid duplicates
6. **Logs all operations** to `./codeartifact-migration/migration.log`

## Output

The script creates a working directory `./codeartifact-migration/` containing:
- `packages-list.json` - List of all packages
- `migration.log` - Detailed operation log
- `packages/` - Temporary directory for package downloads

## Results

At completion, you'll see a summary showing:
- ✓ Successfully copied packages
- ⊘ Skipped packages (already exist)
- ✗ Failed packages

## Notes

- Packages already existing in the target repository are automatically skipped
- The script handles multiple versions of the same package
- All operations are logged for troubleshooting
- Temporary files are cleaned up automatically
