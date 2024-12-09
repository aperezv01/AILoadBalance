@description('The name of the APIM API for OpenAI API')
param openAIAPIName string = 'openai'

@description('The relative path of the APIM API for OpenAI API')
param openAIAPIPath string = 'openai'

@description('The display name of the APIM API for OpenAI API')
param openAIAPIDisplayName string = 'OpenAI'

@description('The description of the APIM API for OpenAI API')
param openAIAPIDescription string = 'Azure OpenAI API inferencing API'

@description('Full URL for the OpenAI API spec')
param openAIAPISpecURL string = 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-02-01/inference.json'

@description('The name of the APIM Subscription for OpenAI API')
param openAISubscriptionName string = 'openai-subscription'

@description('The description of the APIM Subscription for OpenAI API')
param openAISubscriptionDescription string = 'OpenAI Subscription'

@description('The name of the OpenAI backend pool')
param openAIBackendPoolName string = 'openai-backend-pool'

@description('The description of the OpenAI backend pool')
param openAIBackendPoolDescription string = 'Load balancer for multiple OpenAI endpoints'

@description('Existing APIM instance name')
param existingApimName string

@description('Existing APIM resource group')
param existingOpenAIResourceGroup string

@description('List of existing Cognitive Services')
param existingCognitiveServices array

// Reference the existing APIM instance
resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: existingApimName
}

// Reference the existing Cognitive Services
resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = [for service in existingCognitiveServices: {
  name: service.name
  scope: resourceGroup(existingOpenAIResourceGroup)
}]

// Example usage of the existing Cognitive Services

var roleDefinitionID = resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
module roleAssignment 'roleAssignment.bicep' = [for (config, i) in existingCognitiveServices: if(length(existingCognitiveServices) > 0) {
  name: 'roleAssignment${i}'
  scope: resourceGroup(existingOpenAIResourceGroup)
  params: {
    roleDefinitionId: roleDefinitionID
    principalId: apimService.identity.principalId
  }
}]

resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
    name: openAIAPIName
    parent: apimService
    properties: {
      apiType: 'http'
      description: openAIAPIDescription
      displayName: openAIAPIDisplayName
      format: 'openapi-link'
      path: openAIAPIPath
      protocols: [
        'https'
      ]
      subscriptionKeyParameterNames: {
        header: 'api-key'
        query: 'api-key'
      }
      subscriptionRequired: true
      type: 'http'
      value: openAIAPISpecURL
    }
  }

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  name: 'policy'
  parent: api
  properties: {
    format: 'rawxml'
    value: loadTextContent('policy.xml')
  }
}

resource backendOpenAI 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = [for (config, i) in existingCognitiveServices: if(length(existingCognitiveServices) > 0) {
  name: config.name
  parent: apimService
  properties: {
    description: 'backend description'
    url: '${cognitiveServices[i].properties.endpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 1
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT5M'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
            ]
          }
          name: 'openAIBreakerRule'
          tripDuration: 'PT1M'
          acceptRetryAfter: true    // respects the Retry-After header
        }
      ]
    }
  }
}]


resource backendPoolOpenAI 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = if(length(existingCognitiveServices) > 1) {
  name: openAIBackendPoolName
  parent: apimService
  #disable-next-line BCP035 // suppress the false positive as protocol and url are not needed in the Pool type
  properties: {
    description: openAIBackendPoolDescription
    type: 'Pool'
//    protocol: 'http'  // the protocol is not needed in the Pool type
//    url: '${cognitiveServices[0].properties.endpoint}/openai'   // the url is not needed in the Pool type
    pool: {
      services: [for (config, i) in existingCognitiveServices: {
          id: '/backends/${backendOpenAI[i].name}'
          priority: config.priority
          weight: config.weight
        }
      ]
    }
  }
}

resource apimSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  name: openAISubscriptionName
  parent: apimService
  properties: {
    allowTracing: true
    displayName: openAISubscriptionDescription
    scope: '/apis/${api.id}'
    state: 'active'
  }
}

output apimServiceId string = apimService.id

output apimResourceGatewayURL string = apimService.properties.gatewayUrl

#disable-next-line outputs-should-not-contain-secrets
output apimSubscriptionKey string = apimSubscription.listSecrets().primaryKey


