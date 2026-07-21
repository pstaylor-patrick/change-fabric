#!/usr/bin/env bash
# Publishes the built site: syncs site/dist to the Terraform-managed S3 bucket
# and invalidates the www CloudFront distribution so the new build is served
# immediately. Run `npm run build` in site/ first, then `terraform apply` in
# site/infra/, then this. Reads the bucket and distribution id from Terraform
# outputs, so there are no hardcoded ids here.
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-personal}"
export AWS_PAGER=""

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dist="$here/../dist"

if [ ! -f "$dist/index.html" ]; then
  echo "no build found at $dist; run 'npm run build' in site/ first" >&2
  exit 1
fi

bucket="$(terraform -chdir="$here" output -raw site_bucket)"
distribution="$(terraform -chdir="$here" output -raw www_distribution_id)"

echo "syncing $dist -> s3://$bucket"
# Hashed assets get a long cache; index.html must not, so it always reflects the
# latest deploy.
aws s3 sync "$dist" "s3://$bucket" --delete \
  --exclude index.html \
  --cache-control "public, max-age=31536000, immutable"
aws s3 cp "$dist/index.html" "s3://$bucket/index.html" \
  --cache-control "public, max-age=60, must-revalidate" \
  --content-type "text/html"

# The raw spec markdown is fetched directly by agents/tools, so serve it as
# plain markdown text (not the octet-stream the sync would guess) with a short
# cache so a corrected spec propagates.
if compgen -G "$dist/spec/*.md" >/dev/null; then
  for md in "$dist"/spec/*.md; do
    aws s3 cp "$md" "s3://$bucket/spec/$(basename "$md")" \
      --content-type "text/markdown; charset=utf-8" \
      --cache-control "public, max-age=300, must-revalidate"
  done
fi

echo "invalidating CloudFront $distribution"
aws cloudfront create-invalidation --distribution-id "$distribution" --paths "/*" >/dev/null

echo "deployed."
