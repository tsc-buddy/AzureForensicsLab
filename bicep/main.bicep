targetScope = 'subscription' // This solutions deployment scope is at the subscription level. Not resource group level.
param location string = 'australiaeast'
@allowed([
  'npd'
  'dev'
  'tst'
  'prd'
])
param environmentType string = 'dev'
param objectID string = 'xx-xx-xx-xx' // expects your AAD Object ID
param tenantID string = 'xx-xx-xx-xx' //expects your tenant ID


//Resource Group provisioning.
resource rgCore 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: 'rg-foresics-lab-${uniqueString(subscription().id)}'
  location: location
  tags:{
    'environment': environmentType
    'owner': 'Contoso-Cybersec'
  }
}
// Forensics Lab Bicep Modules
module storageLayer 'modules/storage.bicep' = {
  name: 'storageLayer'
  scope: rgCore
  params: {
    location: location
    environmentType: environmentType
  }
}

module loggingLayer 'modules/log.bicep' = {
  name: 'loggingLayer'
  scope: rgCore
  params: {
    location: location
    environmentType: environmentType
  }
}

module secureVault 'modules/keyvault.bicep' = {
  name: 'secureVault'
  scope: rgCore
  params: {
    location: location
    environmentType: environmentType
    objectID: objectID
    tenantID: tenantID
  }
}
module automationEngine 'modules/automationEngine.bicep' = {
  scope: rgCore
  name: 'automationEngine'  
  params: {
    location: location
    environmentType: environmentType
    runbooks: [
      {
        runbookName: 'Windows-HybridWorker-Deployment'
        runbookUri: 'https://raw.githubusercontent.com/azureautomation/Create-Automation-Windows-HybridWorker/main/Create-Windows-HW.ps1'
        runbookType: 'PowerShell'
        logProgress: true
        logVerbose: false
      }
      {
        runbookName: 'VMDigitalEvidenceTrigger'
        runbookUri: 'https://raw.githubusercontent.com/mspnp/solution-architectures/master/forensics/Copy-VmDigitalEvidenceWin.ps1'
        runbookType: 'PowerShell'
        logProgress: true
        logVerbose: false
      }
    ]        
  }
}
