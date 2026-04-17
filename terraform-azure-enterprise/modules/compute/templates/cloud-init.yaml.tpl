#cloud-config
# cloud-init runs once on first boot.
# It installs dependencies and pulls secrets from Key Vault using the VMSS
# managed identity — no credentials are embedded in this file.

package_update: true
packages:
  - curl
  - jq
  - unzip

runcmd:
  # Fetch a token from IMDS using the managed identity
  - |
    TOKEN=$(curl -sf 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' \
      -H 'Metadata: true' | jq -r '.access_token')

  # Retrieve the DB connection string from Key Vault
  - |
    DB_CONN=$(curl -sf "${key_vault_uri}secrets/db-connection-string?api-version=7.3" \
      -H "Authorization: Bearer $TOKEN" | jq -r '.value')
    echo "DB_CONNECTION_STRING=$DB_CONN" >> /etc/app.env

  # Set the environment and port for the application
  - echo "APP_ENVIRONMENT=${environment}" >> /etc/app.env
  - echo "APP_PORT=${app_port}" >> /etc/app.env

  # Start the application (replace with your actual startup command)
  - |
    chmod 600 /etc/app.env
    systemctl enable app.service
    systemctl start app.service
