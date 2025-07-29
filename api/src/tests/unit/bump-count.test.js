import { handler } from "../../handlers/bump-count/index.mjs"
import { mockClient } from "aws-sdk-client-mock"
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb"


const dynamoDBMock = mockClient(DynamoDBDocumentClient);

beforeEach(() => {
  dynamoDBMock.reset()
})


it("Visitor Count is returned", async () => {
  // this is where you mock what DynamoDB is providing inside the lambda
  dynamoDBMock.on(UpdateCommand).resolves({
    Attributes: { visit_count: 1 }
  })

  // it's just a GET endpoint so the payload does not matter
  const result = await handler({})

  // stringify result and check the value
  expect(result.body).toBe(JSON.stringify({ count: 1 }))

})
