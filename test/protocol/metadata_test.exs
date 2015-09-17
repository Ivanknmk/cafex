defmodule Cafex.Protocol.Metadata.Test do
  use ExUnit.Case, async: true

  test "create_request with no topics creates a valid metadata request" do
    good_request = << 3 :: 16, 0 :: 16, 1 :: 32, 3 :: 16, "foo" :: binary, 0 :: 32 >>
    request = Cafex.Protocol.Metadata.create_request(1, "foo", [])
    assert request == good_request
  end

  test "create_request with a single topic creates a valid metadata request" do
    good_request = << 3 :: 16, 0 :: 16, 1 :: 32, 3 :: 16, "foo" :: binary, 1 :: 32, 3 :: 16, "bar" :: binary >>
    request = Cafex.Protocol.Metadata.create_request(1, "foo", ["bar"])
    assert request == good_request
  end

  test "create_request with a multiple topics creates a valid metadata request" do
    good_request = << 3 :: 16, 0 :: 16, 1 :: 32, 3 :: 16, "foo" :: binary, 3 :: 32, 3 :: 16, "bar" :: binary, 3 :: 16, "baz" :: binary, 4 :: 16, "food" :: binary >>
    request = Cafex.Protocol.Metadata.create_request(1, "foo", ["bar", "baz", "food"])
    assert request == good_request
  end

  test "parse_response correctly parses a valid response" do
    response = << 0 :: 32, 1 :: 32, 0 :: 32, 3 :: 16, "foo" :: binary, 9092 :: 32, 1 :: 32, 0 :: 16, 3 :: 16, "bar" :: binary,
      1 :: 32, 0 :: 16, 0 :: 32, 0 :: 32, 0 :: 32, 1 :: 32, 0 :: 32 >>
    expected_response = %Cafex.Protocol.Metadata.Response{
      brokers: [%Cafex.Protocol.Metadata.Broker{host: "foo", node_id: 0, port: 9092}],
      topic_metadatas: [
        %Cafex.Protocol.Metadata.TopicMetadata{error_code: 0, partition_metadatas: [
          %Cafex.Protocol.Metadata.PartitionMetadata{error_code: 0, isrs: [0], leader: 0, partition_id: 0, replicas: []}
        ], topic: "bar"}
      ]
    }

    assert expected_response == Cafex.Protocol.Metadata.parse_response(response)
  end

  test "Response.broker_for_topic returns correct broker for a topic" do
    metadata = %Cafex.Protocol.Metadata.Response{
      brokers: [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9092, port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9093, port: 9093}
      ],
      topic_metadatas: [
        %Cafex.Protocol.Metadata.TopicMetadata{error_code: 0, partition_metadatas: [
          %Cafex.Protocol.Metadata.PartitionMetadata{error_code: 0, isrs: [0], leader: 9092, partition_id: 0, replicas: []}
        ], topic: "bar"}
      ]
    }
    brokers = [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9091}
    ]

    assert Cafex.Protocol.Metadata.Response.broker_for_topic(metadata, brokers, "bar", 0) == %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9092, socket: fake_socket}
  end

  test "Response.broker_for_topic returns nil when the topic is not found" do
    metadata = %Cafex.Protocol.Metadata.Response{
      brokers: [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9092, port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9093, port: 9093}
      ],
      topic_metadatas: [
        %Cafex.Protocol.Metadata.TopicMetadata{error_code: 0, partition_metadatas: [
          %Cafex.Protocol.Metadata.PartitionMetadata{error_code: 0, isrs: [0], leader: 9092, partition_id: 0, replicas: []}
        ], topic: "bar"}
      ]
    }
    brokers = [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9091}
    ]
    assert Cafex.Protocol.Metadata.Response.broker_for_topic(metadata, brokers, "foo", 0) == nil
  end

  test "Response.broker_for_topic returns nil when the partition is not found" do
    metadata = %Cafex.Protocol.Metadata.Response{
      brokers: [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9092, port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9093, port: 9093}
      ],
      topic_metadatas: [
        %Cafex.Protocol.Metadata.TopicMetadata{error_code: 0, partition_metadatas: [
          %Cafex.Protocol.Metadata.PartitionMetadata{error_code: 0, isrs: [0], leader: 9092, partition_id: 0, replicas: []}
        ], topic: "bar"}
      ]
    }
    brokers = [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9091}
    ]

    assert Cafex.Protocol.Metadata.Response.broker_for_topic(metadata, brokers, "bar", 1) == nil
  end

  test "Response.broker_for_topic returns nil when a matching broker is not found" do
    metadata = %Cafex.Protocol.Metadata.Response{
      brokers: [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9092, port: 9092},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", node_id: 9093, port: 9093}
      ],
      topic_metadatas: [
        %Cafex.Protocol.Metadata.TopicMetadata{error_code: 0, partition_metadatas: [
          %Cafex.Protocol.Metadata.PartitionMetadata{error_code: 0, isrs: [0], leader: 9092, partition_id: 0, replicas: []}
        ], topic: "bar"}
      ]
    }
    brokers = [
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9093},
        %Cafex.Protocol.Metadata.Broker{host: "192.168.0.1", port: 9091}
    ]

    assert Cafex.Protocol.Metadata.Response.broker_for_topic(metadata, brokers, "bar", 0) == nil
  end
end
