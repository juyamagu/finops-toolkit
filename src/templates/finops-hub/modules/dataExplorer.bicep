//==============================================================================
// Parameters
//==============================================================================

// @description('Required. Name of the FinOps hub instance. Used to ensure unique resource names.')
// param hubName string

// @description('Required. Suffix to add to the storage account name to ensure uniqueness.')
// @minLength(6) // Min length requirement is to avoid a false positive warning
// param uniqueSuffix string

@description('Optional. Name of the Azure Data Explorer cluster to use for advanced analytics. If empty, Azure Data Explorer will not be deployed. Required to use with Power BI if you have more than $2-5M/mo in costs being monitored. Default: "" (do not use).')
param clusterName string = ''

// https://learn.microsoft.com/azure/templates/microsoft.kusto/clusters?pivots=deployment-language-bicep#azuresku
@description('Optional. Name of the Azure Data Explorer SKU. Default: "Dev(No SLA)_Standard_E2a_v4".')
@allowed([
  'Dev(No SLA)_Standard_E2a_v4' // 2 CPU, 16GB RAM, 24GB cache, $110/mo
  'Dev(No SLA)_Standard_D11_v2' // 2 CPU, 14GB RAM, 78GB cache, $121/mo
  'Standard_D11_v2'             // 2 CPU, 14GB RAM, 78GB cache, $245/mo
  'Standard_D12_v2'
  'Standard_D13_v2'
  'Standard_D14_v2'
  'Standard_D16d_v5'
  'Standard_D32d_v4'
  'Standard_D32d_v5'
  'Standard_DS13_v2+1TB_PS'
  'Standard_DS13_v2+2TB_PS'
  'Standard_DS14_v2+3TB_PS'
  'Standard_DS14_v2+4TB_PS'
  'Standard_E2a_v4'            // 2 CPU, 14GB RAM, 78GB cache, $220/mo
  'Standard_E2ads_v5'
  'Standard_E2d_v4'
  'Standard_E2d_v5'
  'Standard_E4a_v4'
  'Standard_E4ads_v5'
  'Standard_E4d_v4'
  'Standard_E4d_v5'
  'Standard_E8a_v4'
  'Standard_E8ads_v5'
  'Standard_E8as_v4+1TB_PS'
  'Standard_E8as_v4+2TB_PS'
  'Standard_E8as_v5+1TB_PS'
  'Standard_E8as_v5+2TB_PS'
  'Standard_E8d_v4'
  'Standard_E8d_v5'
  'Standard_E8s_v4+1TB_PS'
  'Standard_E8s_v4+2TB_PS'
  'Standard_E8s_v5+1TB_PS'
  'Standard_E8s_v5+2TB_PS'
  'Standard_E16a_v4'
  'Standard_E16ads_v5'
  'Standard_E16as_v4+3TB_PS'
  'Standard_E16as_v4+4TB_PS'
  'Standard_E16as_v5+3TB_PS'
  'Standard_E16as_v5+4TB_PS'
  'Standard_E16d_v4'
  'Standard_E16d_v5'
  'Standard_E16s_v4+3TB_PS'
  'Standard_E16s_v4+4TB_PS'
  'Standard_E16s_v5+3TB_PS'
  'Standard_E16s_v5+4TB_PS'
  'Standard_E64i_v3'
  'Standard_E80ids_v4'
  'Standard_EC8ads_v5'
  'Standard_EC8as_v5+1TB_PS'
  'Standard_EC8as_v5+2TB_PS'
  'Standard_EC16ads_v5'
  'Standard_EC16as_v5+3TB_PS'
  'Standard_EC16as_v5+4TB_PS'
  'Standard_L4s'
  'Standard_L8as_v3'
  'Standard_L8s'
  'Standard_L8s_v2'
  'Standard_L8s_v3'
  'Standard_L16as_v3'
  'Standard_L16s'
  'Standard_L16s_v2'
  'Standard_L16s_v3'
  'Standard_L32as_v3'
  'Standard_L32s_v3'
])
param clusterSku string = 'Dev(No SLA)_Standard_E2a_v4'

@description('Optional. Number of nodes to use in the cluster. Allowed values: 1 for the Basic SKU tier and 2-1000 for Standard. Default: 1 for dev/test SKUs, 2 for standard SKUs.')
@minValue(1)
@maxValue(1000)
param clusterCapacity int = 1

@description('Optional. Forces the table to be updated if different from the last time it was deployed.')
param forceUpdateTag string = utcNow()

@description('Optional. If true, ingestion will continue even if some rows fail to ingest. Default: false.')
param continueOnErrors bool = false

@description('Optional. Azure location to use for the managed identity and deployment script to auto-start triggers. Default: (resource group location).')
param location string = resourceGroup().location

@description('Optional. Tags to apply to all resources.')
param tags object = {}

@description('Optional. Tags to apply to resources based on their resource type. Resource type specific tags will be merged with tags for all resources.')
param tagsByResource object = {}

@description('Required. Name of the Data Factory instance.')
param dataFactoryName string

@description('Optional. Number of days of data to retain in the Data Explorer *_raw tables. Default: 0.')
param rawRetentionInDays int = 0

// @description('Required. Name of the storage account to use for data ingestion.')
// param storageAccountName string

// @description('Required. Name of storage container to monitor for data ingestion.')
// param storageContainerName string

//------------------------------------------------------------------------------
// Variables
//------------------------------------------------------------------------------

var ftkver = any(loadTextContent('ftkver.txt')) // any() is used to suppress a warning the array size (only happens when version does not contain a dash)
var ftkVersion = contains(ftkver, '-') ? split(ftkver, '-')[0] : ftkver
var ftkBranch = contains(ftkver, '-') ? split(ftkver, '-')[1] : ''

//==============================================================================
// Resources
//==============================================================================

//------------------------------------------------------------------------------
// Dependencies
//------------------------------------------------------------------------------

// Get data factory instance
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' existing = {
  name: dataFactoryName
}

// resource storage 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
//   name: storageAccountName

//   resource blobServices 'blobServices' = {
//     name: 'default'

//     resource landingContainer 'containers' = {
//       name: storageContainerName
//     }
//   }
// }

//------------------------------------------------------------------------------
// Cluster + databases
//------------------------------------------------------------------------------

//  Kusto cluster
resource cluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: clusterName
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.Kusto/clusters') ? tagsByResource['Microsoft.Kusto/clusters'] : {})
  sku: {
    name: clusterSku
    tier: startsWith(clusterSku, 'Dev(No SLA)_') ? 'Basic' : 'Standard'
    capacity: startsWith(clusterSku, 'Dev(No SLA)_') ? 1 : (clusterCapacity == 1 ? 2 : clusterCapacity)
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableStreamingIngest: true
  }

  resource ingestionDb 'databases' = {
    name: 'Ingestion'
    location: location
    kind: 'ReadWrite'

    resource ingestionCommonScript 'scripts' = {
      name: 'CommonFunctions'
      properties: {
        scriptContent: loadTextContent('scripts/IngestionSetup.kql')
        continueOnErrors: continueOnErrors
        forceUpdateTag: forceUpdateTag
      }
    }

    resource ingestionSetupScript 'scripts' = {
      name: 'SetupScript'
      properties: {
        scriptContent: replace(replace(replace(replace(loadTextContent('scripts/IngestionSetup.kql'),
          '$$adfPrincipalId$$', dataFactory.identity.principalId),
          '$$adfTenantId$$', dataFactory.identity.tenantId),
          '$$ftkOpenDataFolder$$', empty(ftkBranch) ? 'https://github.com/microsoft/finops-toolkit/releases/download/v${ftkVersion}' : 'https://raw.githubusercontent.com/microsoft/finops-toolkit/${ftkBranch}/src/open-data'),
          '$$rawRetentionInDays$$', string(rawRetentionInDays))
        continueOnErrors: continueOnErrors
        forceUpdateTag: forceUpdateTag
      }
    }
  }

  resource hubDb 'databases' = {
    name: 'Hub'
    location: location
    kind: 'ReadWrite'
    dependsOn: [
      ingestionDb
    ]

    resource ingestionCommonScript 'scripts' = {
      name: 'CommonFunctions'
      properties: {
        scriptContent: loadTextContent('scripts/IngestionSetup.kql')
        continueOnErrors: continueOnErrors
        forceUpdateTag: forceUpdateTag
      }
    }

    resource hubSetupScript 'scripts' = {
      name: 'SetupScript'
      dependsOn: [
        ingestionDb::ingestionSetupScript
      ]
      properties: {
        scriptContent: replace(replace(loadTextContent('scripts/HubSetup.kql'),
          '$$adfPrincipalId$$', dataFactory.identity.principalId),
          '$$adfTenantId$$', dataFactory.identity.tenantId)
        continueOnErrors: continueOnErrors
        forceUpdateTag: forceUpdateTag
      }
    }
  }
}

// //  Authorize Kusto Cluster to read storage
// resource clusterStorageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(cluster.name, storageContainerName, 'Storage Blob Data Contributor')
//   scope: storage::blobServices
//   properties: {
//     description: 'Give "Storage Blob Data Contributor" to the cluster'
//     principalId: cluster.identity.principalId
//     // Required in case principal not ready when deploying the assignment
//     principalType: 'ServicePrincipal'
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       'ba92f5b4-2d11-453d-a403-e96b0029c9fe'  // Storage Blob Data Contributor -- https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage
//     )
//   }
// }

//==============================================================================
// Outputs
//==============================================================================

@description('The resource ID of the cluster.')
output clusterId string = cluster.id

@description('The name of the cluster.')
output clusterName string = cluster.name

@description('The URI of the cluster.')
output clusterUri string = cluster.properties.uri

@description('The name of the database for data ingestion.')
output ingestionDbName string = cluster::ingestionDb.name

@description('The name of the database for queries.')
output hubDbName string = cluster::hubDb.name
