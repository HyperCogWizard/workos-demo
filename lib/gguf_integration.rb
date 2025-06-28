# frozen_string_literal: true

require 'json'
require 'zlib'

# GGUF Integration Layer
# Provides serialization and deserialization for robotics tensor data
# Compatible with GGUF (GPT-Generated Unified Format) principles
module GGUFIntegration
  class GGUFError < StandardError; end

  # GGUF format constants
  GGUF_MAGIC = 'GGUF'
  GGUF_VERSION = 3
  
  # Tensor data types
  TENSOR_TYPES = {
    float32: 0,
    float16: 1,
    int8: 2,
    int16: 3,
    int32: 4,
    cognitive_state: 100,
    device_state: 101,
    hypergraph: 102
  }.freeze

  class GGUFSerializer
    def self.serialize(agent_tensor_data, compress: true)
      # Convert agent tensor data to GGUF-compatible binary format
      header = build_header(agent_tensor_data)
      metadata = build_metadata(agent_tensor_data)
      tensor_data = serialize_tensors(agent_tensor_data)
      
      gguf_data = {
        header: header,
        metadata: metadata,
        tensors: tensor_data,
        created_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%3NZ'),
        format_version: GGUF_VERSION
      }
      
      serialized = JSON.generate(gguf_data)
      compress ? Zlib::Deflate.deflate(serialized) : serialized
    end

    def self.deserialize(gguf_data, compressed: true)
      data = compressed ? Zlib::Inflate.inflate(gguf_data) : gguf_data
      parsed = JSON.parse(data, symbolize_names: true)
      
      validate_format(parsed)
      reconstruct_agent_from_gguf(parsed)
    end

    private

    def self.build_header(agent_data)
      {
        magic: GGUF_MAGIC,
        version: GGUF_VERSION,
        agent_id: agent_data[:agent_id],
        agent_name: agent_data[:agent_name],
        tensor_count: count_tensors(agent_data),
        metadata_size: 0  # Will be calculated later
      }
    end

    def self.build_metadata(agent_data)
      {
        cognitive_dimensions: agent_data[:cognitive_tensor][:shape],
        device_count: agent_data[:device_tensors].size,
        hypergraph_complexity: agent_data[:hypergraph_edges].size,
        tensor_types: extract_tensor_types(agent_data),
        p_system_compatible: true,
        neural_symbolic_ready: true
      }
    end

    def self.serialize_tensors(agent_data)
      tensors = {}
      
      # Serialize cognitive state tensor
      tensors[:cognitive] = {
        type: TENSOR_TYPES[:cognitive_state],
        shape: agent_data[:cognitive_tensor][:shape],
        data: agent_data[:cognitive_tensor][:data],
        metadata: agent_data[:cognitive_tensor][:metadata]
      }
      
      # Serialize device tensors
      tensors[:devices] = {}
      agent_data[:device_tensors].each do |device_id, tensor|
        tensors[:devices][device_id] = {
          type: TENSOR_TYPES[:device_state],
          shape: tensor[:shape],
          data: tensor[:data],
          metadata: tensor[:metadata]
        }
      end
      
      # Serialize hypergraph structure
      tensors[:hypergraph] = {
        type: TENSOR_TYPES[:hypergraph],
        edges: agent_data[:hypergraph_edges],
        adjacency_matrix: build_adjacency_matrix(agent_data[:hypergraph_edges])
      }
      
      tensors
    end

    def self.count_tensors(agent_data)
      1 + # cognitive tensor
      agent_data[:device_tensors].size + # device tensors
      1 # hypergraph tensor
    end

    def self.extract_tensor_types(agent_data)
      types = [:cognitive_state, :hypergraph]
      agent_data[:device_tensors].each_value do |tensor|
        device_type = tensor[:metadata][:type]
        types << (device_type.include?('Sensor') ? :sensor : :actuator)
      end
      types.uniq
    end

    def self.build_adjacency_matrix(edges)
      # Build simple adjacency matrix from hypergraph edges
      nodes = edges.flat_map { |edge| [edge[:source], edge[:target]] }.uniq
      matrix = {}
      
      nodes.each do |node|
        matrix[node] = {}
        nodes.each { |other_node| matrix[node][other_node] = 0.0 }
      end
      
      edges.each do |edge|
        matrix[edge[:source]][edge[:target]] = edge[:weight]
      end
      
      matrix
    end

    def self.validate_format(parsed_data)
      required_keys = [:header, :metadata, :tensors, :format_version]
      missing_keys = required_keys - parsed_data.keys
      
      raise GGUFError, "Invalid GGUF format: missing #{missing_keys}" unless missing_keys.empty?
      raise GGUFError, "Unsupported GGUF version: #{parsed_data[:format_version]}" if parsed_data[:format_version] != GGUF_VERSION
    end

    def self.reconstruct_agent_from_gguf(gguf_data)
      # Reconstruct agent data from GGUF format
      agent_data = {
        agent_id: gguf_data[:header][:agent_id],
        agent_name: gguf_data[:header][:agent_name],
        cognitive_state: gguf_data[:tensors][:cognitive][:data],
        devices: {},
        hypergraph_edges: gguf_data[:tensors][:hypergraph][:edges],
        metadata: gguf_data[:metadata],
        reconstructed_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
      }
      
      # Reconstruct device data
      gguf_data[:tensors][:devices].each do |device_id, tensor_data|
        agent_data[:devices][device_id] = {
          state: tensor_data[:data],
          shape: tensor_data[:shape],
          metadata: tensor_data[:metadata]
        }
      end
      
      agent_data
    end
  end

  # GGUF file operations
  class GGUFFileManager
    def self.save_agent_state(agent, filepath, compress: true)
      gguf_data = GGUFSerializer.serialize(agent.to_gguf_tensor, compress: compress)
      
      File.open(filepath, 'wb') do |file|
        file.write(gguf_data)
      end
      
      {
        success: true,
        filepath: filepath,
        size_bytes: gguf_data.bytesize,
        compressed: compress
      }
    end

    def self.load_agent_state(filepath, compressed: true)
      gguf_data = File.read(filepath, mode: 'rb')
      GGUFSerializer.deserialize(gguf_data, compressed: compressed)
    end

    def self.export_p_system_schema(agent, filepath)
      # Export P-System compatible schema
      p_system_data = {
        membranes: generate_membranes(agent),
        rules: generate_production_rules(agent),
        initial_configuration: agent.to_gguf_tensor,
        schema_version: "1.0"
      }
      
      File.write(filepath, JSON.pretty_generate(p_system_data))
      p_system_data
    end

    private

    def self.generate_membranes(agent)
      membranes = []
      
      # Create membrane for each device
      agent.devices.each do |device_id, device|
        membranes << {
          id: device_id,
          type: device.class.name,
          permeability: device.is_a?(RoboticsMiddleware::Sensor) ? 'input' : 'output',
          capacity: device.tensor_shape.reduce(:*)
        }
      end
      
      # Create cognitive membrane
      membranes << {
        id: 'cognitive_core',
        type: 'CognitiveProcessor',
        permeability: 'bidirectional',
        capacity: Float::INFINITY
      }
      
      membranes
    end

    def self.generate_production_rules(agent)
      rules = []
      
      # Generate sensor -> cognitive rules
      agent.devices.select { |_, d| d.is_a?(RoboticsMiddleware::Sensor) }.each do |sensor_id, _|
        rules << {
          type: 'sensor_input',
          pattern: "#{sensor_id}_data",
          action: 'update_cognitive_belief',
          membrane: 'cognitive_core'
        }
      end
      
      # Generate cognitive -> actuator rules
      agent.devices.select { |_, d| d.is_a?(RoboticsMiddleware::Actuator) }.each do |actuator_id, _|
        rules << {
          type: 'motor_command',
          pattern: 'cognitive_intention',
          action: "#{actuator_id}_execute",
          membrane: actuator_id
        }
      end
      
      rules
    end
  end
end