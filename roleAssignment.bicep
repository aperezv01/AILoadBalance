@description('The principal ID to assign the role to')
param principalId string

@description('The role definition ID for the role assignment')
param roleDefinitionId string

@description('The name of the role assignment')
param roleAssignmentName string = guid(principalId, roleDefinitionId)

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
