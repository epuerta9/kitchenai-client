set dotenv-load := true

# List all available commands
_default:
    @just --list --unsorted

# ----------------------------------------------------------------------
# DEPENDENCIES
# ----------------------------------------------------------------------

# Bootstrap local development environment
@bootstrap:
    hatch env create
    hatch env create dev
    hatch env create docs
    just install


# Install dependencies
@install:
    just run python --version

# Generate and upgrade dependencies
@upgrade:
    just run hatch-pip-compile --upgrade
    just run hatch-pip-compile dev --upgrade

# Clean up local development environment
@clean:
    hatch env prune
    rm -f .coverage.*

# ----------------------------------------------------------------------
# UTILITIES
# ----------------------------------------------------------------------

# Run a command within the dev environnment
@run *ARGS:
    hatch --env dev run {{ ARGS }}

# Get the full path of a hatch environment
@env-path ENV="dev":
    hatch env find {{ ENV }}

# ----------------------------------------------------------------------
# TESTING/TYPES
# ----------------------------------------------------------------------

# Run the test suite, generate code coverage, and export html report
@coverage-html: test
    rm -rf htmlcov
    @just run python -m coverage html --skip-covered --skip-empty

# Run the test suite, generate code coverage, and print report to stdout
coverage-report: test
    @just run python -m coverage report

# Run tests using pytest
@test *ARGS:
    just run coverage run -m pytest {{ ARGS }}

# Run mypy on project
@types:
    just run python -m mypy .

# Run the django deployment checks
@deploy-checks:
    just dj check --deploy


# Generate admin code for a django app
@admin APP:
    just dj admin_generator {{ APP }} | tail -n +2 > kitchenai/{{ APP }}/admin.py

# Collect static files
@collectstatic:
    just dj tailwind --skip-checks build
    just dj collectstatic --no-input --skip-checks
    just dj compress

# ----------------------------------------------------------------------
# DOCS
# ----------------------------------------------------------------------

# Build documentation using Sphinx
@docs-build LOCATION="docs/_build/html":
    sphinx-build docs {{ LOCATION }}

# Install documentation dependencies
@docs-install:
    hatch run docs:python --version

# Serve documentation locally
@docs-serve:
    hatch run docs:sphinx-autobuild docs docs/_build/html --port 8001

# Generate and upgrade documentation dependencies
docs-upgrade:
    just run hatch-pip-compile dev --upgrade

# ----------------------------------------------------------------------
# LINTING / FORMATTING
# ----------------------------------------------------------------------

# Run all formatters
@fmt:
    just --fmt --unstable
    hatch fmt --formatter
    just run pre-commit run pyproject-fmt -a  > /dev/null 2>&1 || true
    just run pre-commit run reorder-python-imports -a  > /dev/null 2>&1 || true
    just run pre-commit run djade -a  > /dev/null 2>&1 || true

# Run pre-commit on all files
@lint:
    hatch --env dev run pre-commit run --all-files

# ----------------------------------------------------------------------
# BUILD UTILITIES
# ----------------------------------------------------------------------

# Bump project version and update changelog
bumpver VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    just run bump-my-version bump {{ VERSION }}
    just run git-cliff --output CHANGELOG.md

    if [ -z "$(git status --porcelain)" ]; then
        echo "No changes to commit."
        git push && git push --tags
        exit 0
    fi

    version="$(hatch version)"
    git add CHANGELOG.md
    git commit -m "Generate changelog for version ${version}"
    git tag -f "v${version}"
    git push && git push --tags

# Build a wheel distribution of the project using hatch
build-wheel:
    #!/usr/bin/env bash
    set -euo pipefail
    export DEBUG="False"
    just collectstatic
    hatch build


# Build linux binary in docker
build-linux-bin:
    mkdir dist || true
    docker build -t build-bin-container . -f deploy/Dockerfile.binary
    docker run -it -v "${PWD}:/app" -w /app --name final-build build-bin-container just build-wheel && just build-bin
    docker cp final-build:/app/dist .
    docker rm -f final-build


# Build docker image
build-docker-image:
    #!/usr/bin/env bash
    set -euo pipefail
    current_version=$(hatch version)
    image_name="kitchenai"
    just install
    docker build -t "${image_name}:${current_version}" -f deploy/Dockerfile .
    docker tag "${image_name}:${current_version}" "${image_name}:latest"
    echo "Built docker image ${image_name}:${current_version}"