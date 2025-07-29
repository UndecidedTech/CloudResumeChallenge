
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";

// Initialize the DynamoDB client
const client = new DynamoDBClient({ region: "us-east-1" });
const docClient = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
  const tableName = "CloudResume"; // Your DynamoDB table name
  const key = { id: "1" }; // The primary key of the item to update

  // This command atomically increments the 'visit_count' attribute.
  // If the item or the 'visit_count' attribute doesn't exist, it initializes it to 1.
  const command = new UpdateCommand({
    TableName: tableName,
    Key: key,
    // This expression adds 1 to the 'visit_count'. If 'visit_count' doesn't exist,
    // it defaults to 0 before adding 1.
    UpdateExpression: "SET visit_count = if_not_exists(visit_count, :start) + :inc",
    ExpressionAttributeValues: {
      ":inc": 1,   // The value to increment by
      ":start": 0, // The initial value if the attribute doesn't exist
    },
    // This tells DynamoDB to return the new value after the update
    ReturnValues: "UPDATED_NEW",
  });

  try {
    // Execute the command and get the updated item
    const { Attributes } = await docClient.send(command);
    const newCount = Attributes.visit_count;

    // Return a successful response with the new count
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*", // Enable CORS
      },
      body: JSON.stringify({ count: newCount }),
    };
  } catch (error) {
    console.error("Error updating DynamoDB:", error);
    // Return an error response
    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
      body: JSON.stringify({ message: "Internal Server Error" }),
    };
  }
};
