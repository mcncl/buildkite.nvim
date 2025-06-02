#!/bin/bash

# validate-version.sh - ZeroVer validation script
# Can be used as a git hook or standalone validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}Success: $1${NC}"
}

info() {
    echo -e "${BLUE}Info: $1${NC}"
}

warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Get version from argument or git tag
VERSION="$1"

if [[ -z "$VERSION" ]]; then
    # Try to get from git tag being created
    if [[ -n "$GIT_TAG" ]]; then
        VERSION="$GIT_TAG"
    else
        error "No version provided. Usage: $0 <version>"
    fi
fi

echo "🔍 Validating version: $VERSION"

# Primary ZeroVer validation
if [[ ! "$VERSION" =~ ^v0\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
    echo ""
    error "❌ Invalid ZeroVer format: $VERSION"
    echo ""
    echo -e "${RED}🚫 This project strictly follows ZeroVer (0-based versioning).${NC}"
    echo -e "${YELLOW}✅ Required format: v0.x.x${NC}"
    echo ""
    echo -e "${BLUE}Valid examples:${NC}"
    echo "  • v0.1.0 (initial release)"
    echo "  • v0.2.0 (new features)"
    echo "  • v0.1.1 (bug fixes)"
    echo "  • v0.2.0-beta.1 (pre-release)"
    echo "  • v0.10.0 (double digits OK)"
    echo ""
    echo -e "${RED}Invalid examples:${NC}"
    echo "  • v1.0.0 (❌ major version not allowed)"
    echo "  • v2.1.0 (❌ major version not allowed)"
    echo "  • 0.1.0 (❌ missing 'v' prefix)"
    echo ""
    echo -e "${BLUE}🔗 Learn more: https://0ver.org/${NC}"
    exit 1
fi

# Extra protection: catch any attempt at v1+ with detailed explanation
if [[ "$VERSION" =~ ^v[1-9] ]]; then
    echo ""
    error "🛑 MAJOR VERSION DETECTED: $VERSION"
    echo ""
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e "${RED}    ZEROVOR VIOLATION DETECTED!        ${NC}"
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo ""
    echo -e "${RED}This project will NEVER release v1.x.x or higher.${NC}"
    echo ""
    echo -e "${YELLOW}🤔 Why ZeroVer?${NC}"
    echo "  • Neovim itself is at 0.10.4 after 9+ years"
    echo "  • FastAPI is at 0.115.x after 6+ years"
    echo "  • React Native is at 0.79.x after 10+ years"
    echo "  • Signals active, evolving software"
    echo "  • No false promises of 'completeness'"
    echo "  • Allows breaking changes as needed"
    echo ""
    echo -e "${GREEN}💡 Suggested alternatives:${NC}"
    if [[ "$VERSION" == "v1.0.0" ]]; then
        echo "  • v0.1.0 (first stable release)"
    elif [[ "$VERSION" =~ ^v1\.([0-9]+)\.([0-9]+) ]]; then
        MINOR=${BASH_REMATCH[1]}
        PATCH=${BASH_REMATCH[2]}
        NEW_MINOR=$((MINOR + 1))
        echo "  • v0.$NEW_MINOR.$PATCH (increment minor instead)"
    elif [[ "$VERSION" =~ ^v([2-9])\.([0-9]+)\.([0-9]+) ]]; then
        MAJOR=${BASH_REMATCH[1]}
        MINOR=${BASH_REMATCH[2]}
        PATCH=${BASH_REMATCH[3]}
        NEW_MINOR=$((MAJOR * 10 + MINOR))
        echo "  • v0.$NEW_MINOR.$PATCH (convert to 0.x scheme)"
    fi
    echo ""
    echo -e "${BLUE}🔗 Embrace ZeroVer: https://0ver.org/${NC}"
    exit 1
fi

# Additional format validations
if [[ "$VERSION" =~ ^0\. ]]; then
    error "Missing 'v' prefix. Use 'v0.x.x' not '0.x.x'"
fi

if [[ "$VERSION" =~ ^v0\.0\.0 ]]; then
    warning "v0.0.0 might be confusing. Consider v0.1.0 for first release."
fi

# Success!
echo ""
success "✅ Valid ZeroVer format: $VERSION"
echo ""
echo -e "${GREEN}🎉 Version $VERSION follows ZeroVer principles!${NC}"
echo -e "${BLUE}📊 You're in great company with projects like:${NC}"
echo "  • Neovim (0.10.4)"
echo "  • FastAPI (0.115.x)"
echo "  • React Native (0.79.x)"
echo "  • Ruff (0.4.x)"
echo "  • Nushell (0.103.x)"
echo ""
echo -e "${GREEN}🚀 Ready to release!${NC}
