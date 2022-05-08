param location string = resourceGroup().location
@allowed([
  'npd'
  'dev'
  'tst'
  'prd'
])
param environmentType string
param sku string = 'Standard'
param tenantID string // expects your tenantId
param objectID string // expects your AAD object ID
param accessPolicies array = [
  {
    tenantId: tenantID
    objectId: objectID
    permissions: {
      keys: [
        'Get'
        'List'
        'Update'
        'Create'
        'Import'
        'Delete'
        'Recover'
        'Backup'
        'Restore'
      ]
      secrets: [
        'Get'
        'List'
        'Set'
        'Delete'
        'Recover'
        'Backup'
        'Restore'
      ]
      certificates: [
        'Get'
        'List'
        'Update'
        'Create'
        'Import'
        'Delete'
        'Recover'
        'Backup'
        'Restore'
        'ManageContacts'
        'ManageIssuers'
        'GetIssuers'
        'ListIssuers'
        'SetIssuers'
        'DeleteIssuers'
      ]
    }
  }
]

var kvName = 'kv-frlab-${uniqueString(resourceGroup().id)}'

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: kvName
  location: location
  tags:{
    'environment': environmentType
    'owner': 'Contoso Cyber-Sec'
  }
  properties:{
    accessPolicies: accessPolicies
    tenantId: tenantID
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    sku:{
      family: 'A'
      name: sku
    }
  }
}
