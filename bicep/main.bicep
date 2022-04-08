targetScope = 'subscription' // This solutions deployment scope is at the subscription level. Not resource group level.
param location string = 'australiaeast'
@allowed([
  'npd'
  'dev'
  'tst'
  'prd'
])
param environmentType string = 'dev'
param environmentName string = 'dev'
param objectID string = 'f00d2ad1-75c7-4eac-a030-15097fd4aa9f' // expects your AAD Object ID
param tenantID string = '92e89507-6193-4c2c-9191-df61a104af02' //expects your tenant ID


//Resource Group provisioning.
resource rgCore 'Microsoft.Resources/resourceGroups@2021-01-01' = {
  name: 'rg-bnz-foresics-lab-${environmentType}'
  location: location
  tags:{
    'environment': environmentName
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
    environmentName: environmentName
  }
}

module loggingLayer 'modules/log.bicep' = {
  name: 'loggingLayer'
  scope: rgCore
  params: {
    location: location
    environmentType: environmentType
    environmentName: environmentName
  }
}

module secureVault 'modules/keyvault.bicep' = {
  name: 'secureVault'
  scope: rgCore
  params: {
    location: location
    environmentType: environmentType
    environmentName: environmentName
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
    environmentName: environmentName
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
