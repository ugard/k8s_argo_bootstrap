# Hoarder/Karakeep - Environment Variables Update

## Required Changes to SealedSecret

The sealed_secret.yaml needs to be regenerated to remove unused variables:

### Variables to REMOVE:
- `HOARDER_VERSION` - no longer used by Karakeep
- `NEXT_PUBLIC_SECRET` - no longer used by Karakeep

### Variables to KEEP:
- `DATA_DIR` - Required
- `NEXTAUTH_SECRET` - Required
- `NEXTAUTH_URL` - Required
- `MEILI_ADDR` - Required (for search)
- `MEILI_MASTER_KEY` - Required (for search in production)
- `OPENAI_API_KEY` - Optional (for automatic tagging)

## How to regenerate the SealedSecret

1. Extract current secrets:
   ```bash
   kubectl -n hoarder get secret hoarder-env -o jsonpath='{.data}' | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' | while read -r line; do
     key=$(echo "$line" | cut -d= -f1)
     value=$(echo "$line" | cut -d= -f2 | base64 -d)
     echo "$key=$value"
   done
   ```

2. Create new secret file (without HOARDER_VERSION and NEXT_PUBLIC_SECRET):
   ```bash
   cat > hoarder-secret.yaml <<EOF
   apiVersion: v1
   kind: Secret
   metadata:
     name: hoarder-env
     namespace: hoarder
   stringData:
     NEXTAUTH_SECRET: "your_existing_secret"
     NEXTAUTH_URL: "your_existing_url"
     MEILI_MASTER_KEY: "your_existing_key"
     OPENAI_API_KEY: "your_existing_key"
   EOF
   ```

3. Seal the new secret:
   ```bash
   kubeseal --controller-namespace=sealed-secrets --controller-name=sealed-secrets \
     -f hoarder-secret.yaml -o yaml > apps/hoarder/sealed_secret.yaml
   ```

## New Features in Karakeep 0.30.0

The update includes new environment variables (optional):

### Database Performance:
- `DB_WAL_MODE: true` - Already added to deployment for better performance

### Asset Storage (optional S3 support):
- `ASSET_STORE_S3_ENDPOINT`
- `ASSET_STORE_S3_BUCKET`
- `ASSET_STORE_S3_ACCESS_KEY_ID`
- `ASSET_STORE_S3_SECRET_ACCESS_KEY`

### Enhanced Crawling:
- `CRAWLER_STORE_PDF` - Store PDF snapshots
- `CRAWLER_FULL_PAGE_ARCHIVE` - Store full page copy
- `CRAWLER_VIDEO_DOWNLOAD` - Download videos with yt-dlp

See full docs: https://docs.karakeep.app/configuration/environment-variables
