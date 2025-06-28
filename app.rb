# frozen_string_literal: true

require 'sinatra'
require 'sinatra/reloader' if development?
require 'dotenv/load'
require 'rack/ssl-enforcer'
require 'securerandom'
require 'faker'
require 'workos'
require 'json'
require_relative 'lib/robotics_middleware'
require_relative 'lib/gguf_integration'
require_relative 'lib/engineering_workbench'

FIVE_MINUTES_IN_SECONDS = 5 * 60

# Initialize Marduk's Robotics Lab Workbench
$workbench = EngineeringWorkbench::ExperimentManager.new

# Create some demo agents and devices for the robotics lab
def initialize_demo_lab
  # Create primary robotics agent
  agent1 = $workbench.create_agent('marduk_agent_01', 'Primary Manipulation Agent')
  
  # Add sensors
  temp_sensor = RoboticsMiddleware::Sensor.new(
    id: 'temp_01', 
    name: 'Temperature Sensor', 
    sensor_type: 'temperature',
    dof: 1, 
    channels: 1
  )
  
  camera_sensor = RoboticsMiddleware::Sensor.new(
    id: 'cam_01', 
    name: 'Vision System', 
    sensor_type: 'camera',
    dof: 6, 
    channels: 3,
    modalities: ['rgb', 'depth', 'infrared']
  )
  
  # Add actuators
  arm_actuator = RoboticsMiddleware::Actuator.new(
    id: 'arm_01', 
    name: 'Robotic Arm', 
    actuator_type: 'servo',
    dof: 6, 
    channels: 1,
    modalities: ['position', 'velocity', 'torque']
  )
  
  gripper_actuator = RoboticsMiddleware::Actuator.new(
    id: 'grip_01', 
    name: 'End Effector', 
    actuator_type: 'gripper',
    dof: 2, 
    channels: 1
  )
  
  # Add devices to agent
  $workbench.add_device_to_agent('marduk_agent_01', temp_sensor)
  $workbench.add_device_to_agent('marduk_agent_01', camera_sensor)
  $workbench.add_device_to_agent('marduk_agent_01', arm_actuator)
  $workbench.add_device_to_agent('marduk_agent_01', gripper_actuator)
  
  # Set initial cognitive state
  agent1.update_cognitive_state(
    goals: ['object_manipulation', 'environment_mapping', 'adaptive_learning'],
    beliefs: {
      workspace_bounds: [-1.0, 1.0, -1.0, 1.0, 0.0, 2.0],
      safety_protocols: ['collision_avoidance', 'emergency_stop'],
      task_complexity: 'moderate'
    },
    intentions: ['scan_environment', 'identify_objects', 'plan_manipulation'],
    memory: {
      learned_objects: [],
      successful_grasps: 0,
      failure_recovery_strategies: []
    }
  )
  
  # Create secondary cognitive agent for distributed cognition
  agent2 = $workbench.create_agent('marduk_agent_02', 'Cognitive Reasoning Agent')
  
  # Add sensor for cognitive input
  reasoning_sensor = RoboticsMiddleware::Sensor.new(
    id: 'cognitive_input_01',
    name: 'Symbolic Reasoning Interface',
    sensor_type: 'cognitive',
    dof: 1,
    channels: 10,
    modalities: ['symbolic', 'neural', 'hybrid']
  )
  
  $workbench.add_device_to_agent('marduk_agent_02', reasoning_sensor)
  
  agent2.update_cognitive_state(
    goals: ['abstract_reasoning', 'knowledge_synthesis', 'meta_learning'],
    beliefs: {
      reasoning_paradigm: 'neural_symbolic',
      knowledge_domains: ['robotics', 'physics', 'planning'],
      inference_depth: 5
    },
    intentions: ['analyze_sensory_data', 'generate_hypotheses', 'update_world_model'],
    memory: {
      concept_hierarchy: {},
      inference_rules: [],
      learned_patterns: []
    }
  )
  
  # Enable distributed cognition
  $workbench.enable_distributed_cognition([
    { id: 'marduk_node_01', address: 'localhost:8001', capabilities: ['perception', 'actuation'] },
    { id: 'marduk_node_02', address: 'localhost:8002', capabilities: ['reasoning', 'planning'] },
    { id: 'marduk_node_03', address: 'cloud.marduk.lab:443', capabilities: ['learning', 'knowledge_base'] }
  ])
end

# Initialize demo lab on startup
initialize_demo_lab

use Rack::SslEnforcer if production?
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(32)

WorkOS.key = ENV['WORKOS_KEY']

use(Rack::Session::Cookie,
  :key => '_rack_session',
  :path => '/',
  :expire_after => 2592000,
  :secret => settings.session_secret
)

get '/' do
  company_name = params['company'] || "demo-#{Time.now.to_i}"
  domain = company_name + '.com'

  organizations = WorkOS::Organizations.list_organizations(
    domains: [domain],
  )

  @organization = organizations&.data&.first ||
    WorkOS::Organizations.create_organization(
      domains: [domain],
      name: domain.partition('.').first,
    )

  @theme = {
    org: params['org'] || 'Cloud App',
    sidebar_color: params['sidebar_color'] || 'fff',
    bg_color: params['bg_color'] || 'fff'
  }

  erb :index, :layout => :layout
end

post '/portal' do
  if params[:intent] == "audit_logs"
    Thread.new {
      ["user.signed_in", "user.signed_out"].each do |action|
        WorkOS::AuditLogs.create_event(
          organization: params[:organization],
          event: {
            action: action,
            occurred_at: Time.now.iso8601(3),
            actor: {
              id: "user_01GBNJC3MX9ZZJW1FSTF4C5938",
              name: Faker::Name.name,
              type: "user"
            },
            targets: [
              {
                id: "team_01GBNJD4MKHVKJGEWK42JNMBGS",
                type: "team"
              }
            ],
            context: {
              location: request.ip,
              user_agent: request.user_agent
            }
          }
        )
      end
     }
  end

  adminPortalLink = WorkOS::Portal.generate_link(
    organization: params[:organization],
    intent: params[:intent]
  )

  redirect adminPortalLink
end

# Robotics Workbench Routes
get '/workbench' do
  @agents = $workbench.agents
  @experiments = $workbench.experiments
  @workbench_state = $workbench.workbench_state
  @tensor_visualizations = $workbench.get_tensor_visualization_data
  
  erb :workbench, :layout => :layout
end

get '/workbench/api/agents' do
  content_type :json
  {
    agents: $workbench.agents.transform_values do |agent|
      {
        id: agent.id,
        name: agent.name,
        devices: agent.devices.transform_values do |device|
          {
            id: device.id,
            name: device.name,
            type: device.class.name,
            state: device.get_state,
            tensor_shape: device.tensor_shape
          }
        end,
        cognitive_state: agent.cognitive_state
      }
    end
  }.to_json
end

get '/workbench/api/tensor_field' do
  content_type :json
  $workbench.get_tensor_visualization_data.to_json
end

post '/workbench/api/agents/:agent_id/devices/:device_id/actuate' do
  agent = $workbench.agents[params[:agent_id]]
  halt 404, 'Agent not found' unless agent
  
  device = agent.devices[params[:device_id]]
  halt 404, 'Device not found' unless device
  halt 400, 'Device is not an actuator' unless device.is_a?(RoboticsMiddleware::Actuator)
  
  request_data = JSON.parse(request.body.read)
  target_position = request_data['target_position'] || 0.0
  
  device.set_target(target_position)
  result = device.execute_motion
  
  content_type :json
  { success: true, device_state: result }.to_json
end

post '/workbench/api/agents/:agent_id/cognitive_update' do
  agent = $workbench.agents[params[:agent_id]]
  halt 404, 'Agent not found' unless agent
  
  request_data = JSON.parse(request.body.read)
  agent.update_cognitive_state(request_data)
  
  content_type :json
  { success: true, cognitive_state: agent.cognitive_state }.to_json
end

get '/workbench/api/agents/:agent_id/gguf_export' do
  agent = $workbench.agents[params[:agent_id]]
  halt 404, 'Agent not found' unless agent
  
  content_type :json
  agent.to_gguf_tensor.to_json
end

post '/workbench/api/experiments' do
  request_data = JSON.parse(request.body.read)
  experiment_id = "exp_#{Time.now.to_i}_#{rand(1000)}"
  
  experiment = $workbench.create_experiment(experiment_id, {
    name: request_data['name'] || "Experiment #{experiment_id}",
    agents: request_data['agents'] || [],
    duration: request_data['duration'] || 300,
    objectives: request_data['objectives'] || []
  })
  
  content_type :json
  {
    success: true,
    experiment: {
      id: experiment.id,
      name: experiment.name,
      state: experiment.state,
      objectives: experiment.objectives
    }
  }.to_json
end

post '/workbench/api/experiments/:experiment_id/start' do
  success = $workbench.start_experiment(params[:experiment_id])
  
  content_type :json
  { success: success }.to_json
end

post '/workbench/api/experiments/:experiment_id/stop' do
  success = $workbench.stop_experiment(params[:experiment_id])
  
  content_type :json
  { success: success }.to_json
end

# HomeAssistant Transformation Routes
get '/homeassistant' do
  @automation_kernels = generate_homeassistant_kernels
  erb :homeassistant, :layout => :layout
end

get '/homeassistant/api/automations' do
  content_type :json
  generate_homeassistant_kernels.to_json
end

# GGUF Export/Import Routes
get '/gguf/export/full_lab' do
  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  filepath = "/tmp/marduk_lab_state_#{timestamp}.gguf"
  
  result = $workbench.export_full_state_as_gguf(filepath)
  
  content_type :json
  { 
    success: true, 
    filepath: filepath,
    download_url: "/gguf/download?file=#{File.basename(filepath)}",
    metadata: result
  }.to_json
end

get '/gguf/download' do
  filename = params['file']
  halt 400, 'Filename required' unless filename
  
  filepath = "/tmp/#{filename}"
  halt 404, 'File not found' unless File.exist?(filepath)
  
  content_type 'application/octet-stream'
  attachment filename
  File.read(filepath, mode: 'rb')
end

# Utility method for HomeAssistant kernelization
def generate_homeassistant_kernels
  # Convert traditional HomeAssistant automations to agentic kernels
  [
    {
      id: 'lighting_cognitive_kernel',
      name: 'Adaptive Lighting Control',
      entity_mappings: ['light.living_room', 'sensor.motion_01', 'sensor.ambient_light'],
      cognitive_function: "(lambda (motion light-level time-of-day) 
                             (if (and motion (< light-level 30)) 
                                 (adjust-brightness (* 100 (- 1 (/ time-of-day 24))))
                                 (fade-off 0.95)))",
      tensor_nodes: [
        { id: 'motion_input', shape: [1, 1], type: 'sensor' },
        { id: 'light_control', shape: [3, 1], type: 'actuator' },
        { id: 'cognitive_state', shape: [10, 1], type: 'memory' }
      ],
      hypergraph_edges: [
        { source: 'motion_input', target: 'cognitive_state', weight: 0.8 },
        { source: 'cognitive_state', target: 'light_control', weight: 0.9 }
      ]
    },
    {
      id: 'hvac_reasoning_kernel', 
      name: 'Climate Control Reasoning Agent',
      entity_mappings: ['climate.main', 'sensor.temperature', 'sensor.humidity', 'sensor.occupancy'],
      cognitive_function: "(lambda (temp humidity occupancy preferences)
                             (let ((comfort-zone (comfort-model preferences occupancy)))
                               (if (outside-zone? temp humidity comfort-zone)
                                   (optimize-climate temp humidity comfort-zone)
                                   (maintain-efficiency))))",
      tensor_nodes: [
        { id: 'environmental_sensors', shape: [3, 4], type: 'sensor' },
        { id: 'climate_actuators', shape: [2, 3], type: 'actuator' },
        { id: 'comfort_model', shape: [5, 5], type: 'neural_network' }
      ],
      hypergraph_edges: [
        { source: 'environmental_sensors', target: 'comfort_model', weight: 1.0 },
        { source: 'comfort_model', target: 'climate_actuators', weight: 0.95 }
      ]
    },
    {
      id: 'security_surveillance_kernel',
      name: 'Neural-Symbolic Security Agent', 
      entity_mappings: ['camera.front_door', 'sensor.door_contact', 'alarm_control_panel.main'],
      cognitive_function: "(lambda (video-stream door-state time-pattern)
                             (let ((threat-assessment (analyze-visual video-stream))
                                   (behavior-model (temporal-analysis time-pattern)))
                               (if (anomaly-detected? threat-assessment behavior-model)
                                   (escalate-security threat-assessment)
                                   (update-baseline behavior-model))))",
      tensor_nodes: [
        { id: 'visual_processing', shape: [480, 640, 3], type: 'cnn' },
        { id: 'temporal_memory', shape: [24, 7], type: 'lstm' },
        { id: 'threat_classifier', shape: [10, 1], type: 'neural_network' }
      ],
      hypergraph_edges: [
        { source: 'visual_processing', target: 'threat_classifier', weight: 0.9 },
        { source: 'temporal_memory', target: 'threat_classifier', weight: 0.7 },
        { source: 'threat_classifier', target: 'security_response', weight: 1.0 }
      ]
    }
  ]
end
