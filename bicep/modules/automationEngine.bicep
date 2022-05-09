
param location string
@allowed([
  'npd'
  'dev'
  'tst'
  'prd'
])
param environmentType string
param sku string = 'Basic'

@description('Runbooks to import into automation account')
@metadata({
  runbookName: 'Runbook name'
  runbookUri: 'Runbook URI'
  runbookType: 'Runbook type: Graph, Graph PowerShell, Graph PowerShellWorkflow, PowerShell, PowerShell Workflow, Script'
  logProgress: 'Enable progress logs'
  logVerbose: 'Enable verbose logs'
})
param runbooks array = []

var autoAccountName = 'auto-frlab-${uniqueString(resourceGroup().id)}'

resource automationAccount 'Microsoft.Automation/automationAccounts@2020-01-13-preview' = {
  name: autoAccountName
  location: location
  tags:{
    'environment': environmentType
    'owner': 'Contoso-Cybersec'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: sku
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2019-06-01' = [for runbook in runbooks: {
  parent: automationAccount
  name: runbook.runbookName
  location: location
  properties: {
    runbookType: runbook.runbookType
    logProgress: runbook.logProgress
    logVerbose: runbook.logVerbose
    publishContentLink: {
      uri: runbook.runbookUri
    }
  }
}]
output systemIdentityPrincipalId string = automationAccount.identity.principalId
