#!/usr/bin/env bash

# shellcheck source=/dev/null
source "./.github/workflows/scripts/e2e-verify.common.sh"

# Script Inputs
BINARY=${BINARY:-}
PROVENANCE=${PROVENANCE:-}
GITHUB_REF=${GITHUB_REF:-}
GITHUB_REF_NAME=${GITHUB_REF_NAME:-}
GITHUB_REF_TYPE=${GITHUB_REF_TYPE:-}
RUNNER_DEBUG=${RUNNER_DEBUG:-}
if [[ -n "${RUNNER_DEBUG}" ]]; then
    set -x
fi

this_file=$(e2e_this_file)
this_branch=$(echo "${this_file}" | cut -d '.' -f4)

# verify_provenance_content verifies provenance content generated by the container-based generator.
verify_provenance_content() {
    # This is always in sigstore bundle format.
    attestation=$(jq -r '.dsseEnvelope.payload' <"$PROVENANCE" | base64 -d)
    echo "${attestation}"
    has_assets=$(echo "${this_file}" | cut -d '.' -f5 | grep assets)
    annotated_tags=$(echo "${this_file}" | cut -d '.' -f5 | grep annotated || true)

    echo "  **** Provenance content verification *****"

    # Verify all common provenance fields.
    e2e_verify_common_all_v1 "${attestation}"

    e2e_verify_predicate_subject_name "${attestation}" "$BINARY"
    e2e_verify_predicate_v1_runDetails_builder_id "${attestation}" "https://github.com/slsa-framework/slsa-github-generator/.github/workflows/builder_container-based_slsa3.yml@refs/heads/main"
    e2e_verify_predicate_v1_buildDefinition_buildType "${attestation}" "https://slsa.dev/container-based-build/v0.1?draft"

    # Ignore tha annotated tags, because they are not part of a release.
    if [[ "$GITHUB_REF_TYPE" == "tag" ]] && [[ -z "$annotated_tags" ]]; then
        assets=$(e2e_get_release_assets_filenames "$GITHUB_REF_NAME")
        if [[ -z "$has_assets" ]]; then
            e2e_assert_eq "$assets" "[\"null\",\"null\"]" "there should be no assets"
        else
            multi_subjects=$(echo "${this_file}" | cut -d '.' -f5 | grep multi-subjects)
            if [[ -n "$multi_subjects" ]]; then
                e2e_assert_eq "$assets" "[\"multiple.intoto.jsonl\",\"null\"]" "there should be assets"
            else
                e2e_assert_eq "$assets" "[\"hello.intoto.jsonl\",\"null\"]" "there should be assets"
            fi
        fi
    fi
}

echo "branch is ${this_branch}"
echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"
echo "GITHUB_REF_TYPE: $GITHUB_REF_TYPE"
echo "GITHUB_REF: $GITHUB_REF"
echo "DEBUG: file is ${this_file}"

# Verify provenance authenticity.
export SLSA_VERIFIER_EXPERIMENTAL="1"
export SLSA_VERIFIER_TESTING="true"

e2e_run_verifier_all_releases "v1.7.0"

# Verify the provenance content.
verify_provenance_content
