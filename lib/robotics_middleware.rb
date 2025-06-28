# frozen_string_literal: true

# Robotics Middleware Abstraction Layer
# Provides core abstractions for devices, agents, and tensor operations
module RoboticsMiddleware
  # Base class for all robotics devices
  class Device
    attr_reader :id, :name, :dof, :channels, :modalities, :tensor_shape

    def initialize(id:, name:, dof: 1, channels: 1, modalities: ['position'])
      @id = id
      @name = name
      @dof = dof  # Degrees of Freedom
      @channels = channels
      @modalities = modalities
      @tensor_shape = [dof, channels, modalities.length]
      @state = {}
    end

    def update_state(new_state)
      @state.merge!(new_state)
      @state[:timestamp] = Time.now.to_f
    end

    def get_state
      @state.dup
    end

    def to_tensor
      # Simple tensor representation for GGUF serialization
      {
        shape: @tensor_shape,
        data: @state,
        metadata: {
          id: @id,
          name: @name,
          type: self.class.name
        }
      }
    end
  end

  # Sensor device implementation
  class Sensor < Device
    def initialize(id:, name:, sensor_type: 'generic', **opts)
      super(id: id, name: name, **opts)
      @sensor_type = sensor_type
    end

    def read_data
      # Simulate sensor data reading
      case @sensor_type
      when 'temperature'
        update_state(value: 20.0 + rand(10.0), unit: 'celsius')
      when 'distance'
        update_state(value: rand(100.0), unit: 'cm')
      when 'camera'
        update_state(
          width: 640,
          height: 480,
          channels: 3,
          data: "simulated_image_data_#{Time.now.to_i}"
        )
      else
        update_state(value: rand(100.0))
      end
      get_state
    end
  end

  # Actuator device implementation  
  class Actuator < Device
    def initialize(id:, name:, actuator_type: 'servo', **opts)
      super(id: id, name: name, **opts)
      @actuator_type = actuator_type
      @target_position = 0.0
    end

    def set_target(position)
      @target_position = position
      update_state(
        target: position,
        current: @state[:current] || 0.0,
        error: position - (@state[:current] || 0.0)
      )
    end

    def execute_motion
      # Simulate actuator movement
      current = @state[:current] || 0.0
      error = @target_position - current
      new_position = current + (error * 0.1) # Simple proportional control
      
      update_state(
        current: new_position,
        target: @target_position,
        error: @target_position - new_position
      )
      get_state
    end
  end

  # Agent for cognitive control
  class Agent
    attr_reader :id, :name, :devices, :cognitive_state

    def initialize(id:, name:)
      @id = id
      @name = name
      @devices = {}
      @cognitive_state = {
        goals: [],
        beliefs: {},
        intentions: [],
        memory: {}
      }
    end

    def add_device(device)
      @devices[device.id] = device
    end

    def remove_device(device_id)
      @devices.delete(device_id)
    end

    def update_cognitive_state(state_update)
      @cognitive_state.merge!(state_update)
      @cognitive_state[:last_update] = Time.now.to_f
    end

    def to_gguf_tensor
      # Convert agent state to GGUF-compatible tensor format
      {
        agent_id: @id,
        agent_name: @name,
        device_tensors: @devices.transform_values(&:to_tensor),
        cognitive_tensor: {
          shape: [1, @cognitive_state.keys.length],
          data: @cognitive_state,
          metadata: {
            type: 'cognitive_state',
            schema_version: '1.0'
          }
        },
        hypergraph_edges: generate_device_connections,
        timestamp: Time.now.to_f
      }
    end

    private

    def generate_device_connections
      # Simple hypergraph representation of device connections
      connections = []
      sensor_ids = @devices.select { |_, d| d.is_a?(Sensor) }.keys
      actuator_ids = @devices.select { |_, d| d.is_a?(Actuator) }.keys
      
      # Create sensor -> actuator edges for control loops
      sensor_ids.each do |sensor_id|
        actuator_ids.each do |actuator_id|
          connections << {
            type: 'control_loop',
            source: sensor_id,
            target: actuator_id,
            weight: 1.0
          }
        end
      end
      
      connections
    end
  end
end