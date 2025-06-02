#!/bin/bash

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

info() {
    echo -e "${BLUE}Info: $1${NC}"
}

success() {
    echo -e "${GREEN}Success: $1${NC}"
}

warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Check if we're in the right directory
if [[ ! -f "lua/buildkite/init.lua" ]]; then
    error "Please run this script from the root of the buildkite.nvim repository"
fi

# Check if git working directory is clean
if [[ -n $(git status --porcelain) ]]; then
    error "Working directory is not clean. Please commit or stash your changes."
fi

# Check if we're on main branch
current_branch=$(git branch --show-current)
if [[ "$current_branch" != "main" ]]; then
    warning "You're not on the main branch (currently on: $current_branch)"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get version from user input
if [[ -z "$1" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v0.1.0"
    echo "         $0 v0.2.0-beta.1"
    exit 1
fi

VERSION="$1"

# Validate version format (ZeroVer - must start with v0.)
if [[ ! "$VERSION" =~ ^v0\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
    echo ""
    error "❌ Invalid version format: $VERSION"
    echo ""
    echo -e "${RED}🚫 This project strictly follows ZeroVer (0-based versioning).${NC}"
    echo -e "${YELLOW}✅ Valid format: v0.x.x${NC}"
    echo -e "${BLUE}Examples:${NC}"
    echo "  • v0.1.0 (initial release)"
    echo "  • v0.2.0 (new features)"
    echo "  • v0.1.1 (bug fixes)"
    echo "  • v0.2.0-beta.1 (pre-release)"
    echo ""
    echo -e "${BLUE}❌ Invalid examples:${NC}"
    echo "  • v1.0.0 (major version not allowed)"
    echo "  • v2.1.0 (major version not allowed)"
    echo ""
    echo -e "${BLUE}🔗 Learn more about ZeroVer: https://0ver.org/${NC}"
    exit 1
fi

# Additional check: reject any version starting with v1 or higher
if [[ "$VERSION" =~ ^v[1-9] ]]; then
    echo ""
    error "🛑 STOP! Version $VERSION violates ZeroVer principles!"
    echo ""
    echo -e "${RED}This project will NEVER release v1.x.x or higher.${NC}"
    echo -e "${YELLOW}Like Neovim itself (0.10.4), we stay in 0.x forever.${NC}"
    echo ""
    echo -e "${BLUE}Why ZeroVer?${NC}"
    echo "  • Signals active development"
    echo "  • Allows breaking changes"
    echo "  • No false promises of 'completeness'"
    echo "  • Follows successful projects like Neovim, FastAPI, React Native"
    echo ""
    echo -e "${GREEN}Use v0.x.x instead!${NC}"
    exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^$VERSION$"; then
    error "Tag $VERSION already exists"
fi

info "Preparing release $VERSION"

# Update CHANGELOG.md
if [[ -f "CHANGELOG.md" ]]; then
    # Get changes since last tag
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [[ -n "$LAST_TAG" ]]; then
        info "Getting changes since $LAST_TAG"
        CHANGES=$(git log ${LAST_TAG}..HEAD --pretty=format:"- %s (%h)" --no-merges)
    else
        info "Getting all changes (first release)"
        CHANGES=$(git log --pretty=format:"- %s (%h)" --no-merges)
    fi
    
    # Create temp changelog entry
    TEMP_CHANGELOG=$(mktemp)
    
    # Add new version entry
    echo "## [$VERSION] - $(date +%Y-%m-%d)" > "$TEMP_CHANGELOG"
    echo "" >> "$TEMP_CHANGELOG"
    echo "### Changed" >> "$TEMP_CHANGELOG"
    echo "$CHANGES" >> "$TEMP_CHANGELOG"
    echo "" >> "$TEMP_CHANGELOG"
    
    # Append existing changelog (skip the first unreleased section)
    if grep -q "## \[Unreleased\]" CHANGELOG.md; then
        # Find line after unreleased section and append rest
        awk '/^## \[Unreleased\]/{flag=1; next} flag && /^## /{flag=0} !flag{print}' CHANGELOG.md >> "$TEMP_CHANGELOG"
    else
        # No unreleased section, append everything after header
        tail -n +8 CHANGELOG.md >> "$TEMP_CHANGELOG"
    fi
    
    # Replace changelog
    head -n 7 CHANGELOG.md > CHANGELOG.md.new
    cat "$TEMP_CHANGELOG" >> CHANGELOG.md.new
    mv CHANGELOG.md.new CHANGELOG.md
    rm "$TEMP_CHANGELOG"
    
    info "Updated CHANGELOG.md"
fi

# Run tests
info "Running tests..."
if command -v nvim >/dev/null 2>&1; then
    # Test basic loading
    nvim --headless -c "lua require('buildkite')" -c "qa!" || error "Plugin failed to load"
    success "Basic tests passed"
else
    warning "Neovim not found, skipping tests"
fi

# Show what we're about to do
echo ""
info "Ready to create release $VERSION with the following changes:"
echo ""
if [[ -n "$CHANGES" ]]; then
    echo "$CHANGES"
else
    echo "No changes detected"
fi
echo ""

read -p "Proceed with release? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Release cancelled"
fi

# Commit changelog if it was modified
if [[ -n $(git status --porcelain CHANGELOG.md) ]]; then
    info "Committing CHANGELOG.md update"
    git add CHANGELOG.md
    git commit -m "chore: update CHANGELOG.md for $VERSION"
fi

# Create and push tag
info "Creating tag $VERSION"
git tag -a "$VERSION" -m "Release $VERSION"

info "Pushing tag to origin"
git push origin "$VERSION"

# Also push any changelog commits
if [[ "$current_branch" == "main" ]]; then
    git push origin main
fi

success "Release $VERSION created successfully!"
info "GitHub Actions will automatically create the release page"
info "View releases at: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^/]*\/[^/]*\).*/\1/' | sed 's/\.git$//')/releases"
info ""
echo ""
success "🎉 ZeroVer release $VERSION created successfully!"
echo ""
echo -e "${BLUE}📊 ZeroVer Stats:${NC}"
echo "  • Like Neovim (0.10.4), FastAPI (0.115.x), React Native (0.79.x)"
echo "  • Signals active development and innovation"
echo "  • Allows rapid iteration without version pressure"
echo ""
echo -e "${GREEN}🚀 Your plugin is in excellent company!${NC}"