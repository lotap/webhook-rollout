#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Fail a pipe if any command in it fails.
set -e -o pipefail

# === Helper Functions ===

# Generic update function for Dockerfile ARGs
update_dockerfile_arg() {
	local arg_name=$1
	local new_version=$2
	local prefix=$3 # Optional prefix like '~'

	echo "Updating ${arg_name} to ${prefix}${new_version}"
	perl -pi -e "s|^ARG ${arg_name}[[:space:]]*=[[:space:]]*.*|ARG ${arg_name}=${prefix}${new_version}|" Dockerfile
}

# Function to parse the output of apk policy and update dockerfile with the latest version 
process_and_update_apk_version() {
	local arg_var="$1"
	local pkg_name="$2"
	local policy_output="$3"

	# Parse the version from the provided text block
	local latest_ver
	latest_ver=$(echo "$policy_output" | grep -Eo '^\s+[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+' | head -n 1 | awk '{print $1}')

	# Check if a valid version was found and update the Dockerfile
	if [ -n "$latest_ver" ] && [ "$latest_ver" != "policy:" ]; then
		echo "  Found version for '${pkg_name}': ${major_minor_ver} (from ${latest_ver})"
		update_dockerfile_arg "$arg_var" "$latest_ver"
	else
		echo "  Could not parse version for '${pkg_name}'. Skipping."
	fi
}

# Function to get the latest APK package versions for all packages at once
update_all_apk_packages() {
	local alpine_version=$1
	local packages_file=$2

	# Check if there are any packages to update
	if [ ! -s "$packages_file" ]; then
		echo "No APK packages to update."
		return
	fi

	echo "--> Checking all APK packages on Alpine ${alpine_version}"

	# Build the apk policy command for all packages
	local policy_commands=""
	local package_list=""
	while IFS='=' read -r arg_var pkg_name; do
		if [ -n "$arg_var" ] && [ -n "$pkg_name" ]; then
			policy_commands="${policy_commands}echo '=== ${arg_var}:${pkg_name} ==='; apk policy ${pkg_name} 2>/dev/null || echo 'ERROR: ${pkg_name}'; "
			package_list="${package_list} ${pkg_name}"
		fi
	done < "$packages_file"

	if [ -z "$policy_commands" ]; then
		echo "No valid APK packages found to check."
		return
	fi

	echo "Packages to check:${package_list}"

	# Run single container to check all packages
	local apk_output
	if apk_output=$(timeout 60 docker run --rm "alpine:${alpine_version}" sh -c \
		"apk update > /dev/null 2>&1 && ${policy_commands}"); then

		# Parse the output for each package
		while IFS='=' read -r arg_var pkg_name; do
			if [ -n "$arg_var" ] && [ -n "$pkg_name" ]; then
				echo "Processing ${pkg_name} (${arg_var})..."

				# Extract the section for this specific package
				local package_section
				package_section=$(echo "$apk_output" | awk "
					/=== ${arg_var}:${pkg_name} ===/ { found=1; next }
					found && /=== .* ===/ { found=0 }
					found { print }
				")

				# Handle error cases
				if echo "$package_section" | grep -q "ERROR: ${pkg_name}"; then
					echo "  Could not find package '${pkg_name}'. Skipping."
					continue
				fi

				# Extract version from the policy output and update Dockerfile
				process_and_update_apk_version "$arg_var" "$pkg_name" "$package_section"
			fi
		done < "$packages_file"

	else
		echo "Failed to check APK packages. Container execution failed."
		# Fallback to individual package checks if batch fails
		echo "Falling back to individual package checks..."
		while IFS='=' read -r arg_var pkg_name; do
			if [ -n "$arg_var" ] && [ -n "$pkg_name" ]; then
				update_single_apk_package "$arg_var" "$pkg_name" "$alpine_version"
			fi
		done < "$packages_file"
	fi
}

# Fallback function for individual package checks
update_single_apk_package() {
	local arg_var=$1
	local pkg_name=$2
	local alpine_version=$3
	echo "--> Checking individual APK package '${pkg_name}'"

	local policy_output
	if policy_output=$(timeout 30 docker run --rm "alpine:${alpine_version}" sh -c \
		"apk update > /dev/null 2>&1 && apk policy ${pkg_name} 2>/dev/null"); then

		process_and_update_apk_version "$arg_var" "$pkg_name" "$policy_output"

	else
		echo "Failed to check APK package '${pkg_name}'. Skipping."
	fi
}

# Generic function to get the latest GitHub release tag
update_github_release() {
	local arg_var=$1
	local repo_slug=$2 # Format: "owner/repo"
	echo "--> Checking GitHub release for '${repo_slug}'"

	local latest_tag
	local auth_header=""

	# Use GitHub token if available for higher rate limits
	if [ -n "${GITHUB_TOKEN}" ]; then
		auth_header="Authorization: token ${GITHUB_TOKEN}"
	fi

	if latest_tag=$(curl --silent --fail --max-time 10 \
		${auth_header:+-H "$auth_header"} \
		"https://api.github.com/repos/${repo_slug}/releases/latest" | jq -r .tag_name); then

		if [ -n "$latest_tag" ] && [ "$latest_tag" != "null" ]; then
			update_dockerfile_arg "$arg_var" "$latest_tag"
		else
			echo "No valid release found for GitHub repo '${repo_slug}'. Skipping."
		fi
	else
		echo "Failed to fetch release for GitHub repo '${repo_slug}'. Skipping."
	fi
}

# === SCRIPT STARTS HERE ===

echo "Starting Dockerfile dependency update..."

# Check prerequisites
if ! command -v docker &> /dev/null; then
	echo "Error: Docker is required but not installed."
	exit 1
fi

if ! command -v jq &> /dev/null; then
	echo "Error: jq is required but not installed."
	exit 1
fi

# === 1. Dynamic Discovery of All Dependencies ===
echo "Discovering dependencies from Dockerfile..."

# Use temp files for associative arrays to avoid subshell issues
GITHUB_RELEASES_FILE=$(mktemp)
APK_PACKAGES_FILE=$(mktemp)

# Cleanup temp files on exit
trap 'rm -f "$GITHUB_RELEASES_FILE" "$APK_PACKAGES_FILE"' EXIT

# Discover GitHub releases by parsing URLs
echo "--> Searching for GitHub release definitions (_RELEASE)..."
RELEASE_ARGS=$(grep -o "ARG[[:space:]]*[A-Z0-9_]*_RELEASE" Dockerfile | sed 's/ARG[[:space:]]*//' || true)

if [ -n "$RELEASE_ARGS" ]; then
	# Create a "flattened" version of the Dockerfile
	FLAT_DOCKERFILE=$(tr -d '\\\n' < Dockerfile)

	for arg_var in $RELEASE_ARGS; do
		if [[ "$FLAT_DOCKERFILE" =~ https://api.github.com/repos/([a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+)/.*/\$\{${arg_var}\} ]]; then
			repo_slug="${BASH_REMATCH[1]}"
			echo "$arg_var=$repo_slug" >> "$GITHUB_RELEASES_FILE"
			echo "Found GitHub release mapping: ${arg_var} -> ${repo_slug}"
		else
			echo "Warning: Could not find a valid GitHub URL usage for ARG '${arg_var}'."
		fi
	done
fi

# Discover APK packages from the 'apk add' command
echo "--> Searching for APK package definitions (_VERSION)..."
sed -n '/apk add/,/[^\\]$/p' Dockerfile | \
  grep -E '[a-zA-Z0-9-]+=\$\{[A-Z0-9_]*_VERSION\}' | \
  sed -E 's/^[[:space:]]*([a-zA-Z0-9-]+)=\$\{([A-Z0-9_]*_VERSION)\}.*/\2=\1/' \
  >> "$APK_PACKAGES_FILE"

# Display discovered APK packages
while IFS='=' read -r arg_var pkg_name; do
	echo "Found APK mapping: ${arg_var} -> ${pkg_name}"
done < "$APK_PACKAGES_FILE"

# === 2. Execute Updates ===
echo "Updating Alpine base image..."
if LATEST_ALPINE=$(curl --silent --fail --max-time 10 \
	"https://hub.docker.com/v2/repositories/library/alpine/tags/?page_size=100" | \
	jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1); then

	update_dockerfile_arg "ALPINE_VERSION" "$LATEST_ALPINE"
else
	echo "Failed to fetch latest Alpine version. Skipping."
fi

# Get current Alpine version more safely
CURRENT_ALPINE_VERSION=$(grep "^ARG ALPINE_VERSION" Dockerfile | cut -d'=' -f2)
if [ -z "$CURRENT_ALPINE_VERSION" ]; then
	echo "Warning: Could not determine current Alpine version. Using 3.22.0 as fallback."
	CURRENT_ALPINE_VERSION="3.22.0"
fi

echo "Using Alpine version: $CURRENT_ALPINE_VERSION"

echo "Updating discovered APK packages..."
update_all_apk_packages "$CURRENT_ALPINE_VERSION" "$APK_PACKAGES_FILE"

echo "Updating discovered GitHub releases..."
while IFS='=' read -r arg_var repo_slug; do
	[ -n "$arg_var" ] && update_github_release "$arg_var" "$repo_slug"
done < "$GITHUB_RELEASES_FILE"

echo "Dockerfile dependency check complete."
