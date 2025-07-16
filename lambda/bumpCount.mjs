import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "your-aws-region" }); // e.g., "us-east-1"
const docClient = DynamoDBDocumentClient.from(client);

exports.handler = async (event) => {
  const itemIdToUpdate = "1";
  const tableName = "CloudResume";
  const countAttributeName = "count";

  const params = {
    TableName: tableName,
    Key: {
      id: itemIdToUpdate,
    },
    UpdateExpression: `SET #counter = #counter + :increment`, // Increment the counter by 1
    ExpressionAttributeNames: {
      "#counter": countAttributeName,
    },
    ExpressionAttributeValues: {
      ":increment": 1, // Value to add to the counter
    },
    ReturnValues: "UPDATED_NEW", // Return the updated value
  };

  try {
    const data = await docClient.send(new UpdateCommand(params));
    console.log("UpdateItem succeeded:", data.Attributes);

    const response = {
      statusCode: 200,
      body: JSON.stringify({ message: "Count incremented", updatedItem: data.Attributes }),
    };
    return response;
  } catch (error) {
    console.error("Error updating item:", error);

    const response = {
      statusCode: 500,
      body: JSON.stringify({ message: "Error updating item", error: error.message }),
    };
    return response;
  }
};
