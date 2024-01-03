using Statistics

# Define abstract supertypes
abstract type AbstractNeuron end
abstract type AbstractSynapse end
abstract type AbstractAstrocyte end

# Neuron struct
mutable struct Neuron <: AbstractNeuron
	membrane_potential::Float64
	threshold::Float64
	reset_potential::Float64
	spike_τ::Float64
	out_synapses::Vector{AbstractSynapse}  # Specify the concrete type for clarity
	in_synapses::Vector{AbstractSynapse}   # Specify the concrete type for clarity
	last_spike::Float64
	spike_train::Vector{Int}       # Binary spike train (1 for spike, 0 for no spike)
	linked_astrocytes::Vector{AbstractAstrocyte}
end

function initialize_neurons(num_neurons::Int; simulation_length::Int=100)
	neurons = Vector{Neuron}()
	for _ in 1:num_neurons
		type = rand()<0.8 ? "excitatory" : "inhibitory"

		neuron = Neuron(
			0.0,  # Rest voltage
			5.0,  # Example threshold
			-0.7,  # Rest voltage after spike
			type == "excitatory" ? 1.7 : -1.7,  # Spike amplitude
			[],   # No synapses initially
			[],   # No synapses initially
			-Inf, # Initialize as if never spiked
			zeros(Int, simulation_length),  # Binary spike train
			[]   # No astrocytes initially
		)
		push!(neurons, neuron)
	end
	return neurons
end

# Synapse struct
mutable struct Synapse <: AbstractSynapse
	weight::Float64
	weight_cap::Tuple{Float64, Float64}
	pre_neuron::AbstractNeuron           # Use Neuron type for direct access to properties
	post_neuron::AbstractNeuron          # Use Neuron type for direct access to properties
	T_pre::Float64               # Pre-synaptic trace
	T_post::Float64              # Post-synaptic trace
	delay_const::Float64
	delay_count::Float64
end

# Function to initialize Synapses
function initialize_synapses(num_synapses::Int, neurons::Vector{Neuron})
	synapses = Vector{Synapse}()
	for _ in 1:num_synapses

		pre_neuron = rand(neurons)
		post_neuron = rand(neurons)

		# type = rand()<8 ? "excitatory" : "inhibitory"

		synapse = Synapse(
			rand(0:0.1:3),
			(0.0,3.0),
			pre_neuron,
			post_neuron,
			0.0,
			0.0,
			3.0,
			0.0
		)
		push!(synapses, synapse)
		push!(pre_neuron.out_synapses, synapse)
		push!(post_neuron.in_synapses, synapse)
	end
	return synapses
end

# Astrocyte struct
mutable struct Astrocyte <: AbstractAstrocyte
	A_astro::Float64
	τ_astro::Float64
	w_astro::Float64
	b_astro::Float64
	Γ_astro::Float64
	liquid_neurons::Vector{AbstractNeuron}
end
function initialize_astrocytes(num_astrocytes::Int, liquid_neurons::Vector{Neuron})
	astrocytes = Vector{Astrocyte}()
	for _ in 1:num_astrocytes
		modulated_neurons = rand(liquid_neurons, 100)
		# modulated_neurons = liquid_neurons

		astrocyte = Astrocyte(
			0.15,      	# Initial A_astro value
			10.0,     	# τ_astro should be set according to your model specifics
			7.5e-3,       # w_astro, the weight for the astrocyte's influence
			0.01,      	# b_astro, bias or base level of astrocyte's activity
			0.9, 		# Γ_astro, the gain for the astrocyte's influence
			modulated_neurons
		)
		push!(astrocytes, astrocyte)
		for n in modulated_neurons
			push!(n.linked_astrocytes, astrocyte)
		end
	end
	return astrocytes
end

# LIF Neuron update function
function neuron_LIF_update!(neuron::Neuron, current_time::Int, u_i::Float64, Δt::Float64)
	τ_v = 64.0
	θ_i = neuron.threshold
	absolute_refractory_period = 2.0  # Absolute refractory period duration in milliseconds

    # Check if the neuron is in the refractory period
    if !(current_time - neuron.last_spike < absolute_refractory_period)
		# Check for spikes and reset if necessary
		if neuron.membrane_potential >= θ_i
			neuron.membrane_potential = neuron.reset_potential
			neuron.spike_train[current_time] = 1  # Record spike at the current time index
			neuron.last_spike = current_time
		else
			# Update the membrane potential using Euler integration
			neuron.membrane_potential += (-neuron.membrane_potential + u_i) * (Δt / τ_v)
		end
	end
end

# LIF update function for all neurons
function neurons_LIF_update!(neurons::Vector{Neuron}, current_time::Int, u_i::Vector{Float64}, Δt::Float64)
	u_i = u_i |> x -> [x; zeros(length(neurons) - length(x))]
	
	for (neuron, current) in zip(neurons, u_i)
		neuron_LIF_update!(neuron, current_time, current, Δt)
	end
end

# STDP Synapse update function
function synapse_STDP_update!(synapse::Synapse, current_time::Int, Δt::Float64)
	if synapse.pre_neuron.linked_astrocytes != []
		# A_minus = synapse.pre_neuron.linked_astrocytes[1].A_astro
		A_minus = mean([astrocyte.A_astro for astrocyte in synapse.pre_neuron.linked_astrocytes])
	else
		A_minus = 0.15
	end

	A_plus = 0.15
		
	τ_plus = 10.0  # ms
	τ_minus = 10.0  # ms
	a_plus = 0.1
	a_minus = 0.1

	# Transmit current to post-synaptic neuron
	if synapse.pre_neuron.spike_train[current_time] == 1
		synapse.delay_count = synapse.delay_const
	end

	if synapse.delay_count > 0
		synapse.delay_count -= 1.0
		if synapse.delay_count == 0 && !(current_time - synapse.post_neuron.last_spike < 2)
			synapse.post_neuron.membrane_potential += synapse.weight * synapse.pre_neuron.spike_τ
		end
	end

	# # Update traces based on the spike train
	# T_pre_decay = exp(-Δt / τ_plus)
	# T_post_decay = exp(-Δt / τ_minus)

	# synapse.T_pre = synapse.T_pre * T_pre_decay + a_plus * synapse.pre_neuron.spike_train[current_time]
	# synapse.T_post = synapse.T_post * T_post_decay + a_minus * synapse.post_neuron.spike_train[current_time]

	# Update traces based on the spike train
	synapse.T_pre += (-synapse.T_pre + a_plus * synapse.pre_neuron.spike_train[current_time]) * (Δt / τ_plus)
	synapse.T_post += (-synapse.T_post + a_minus * synapse.post_neuron.spike_train[current_time]) * (Δt / τ_minus)

	# STDP weight update based on the last spike times
	if synapse.pre_neuron.spike_train[current_time] == 1
		# Potentiation due to pre-synaptic spike
		synapse.weight += A_plus * synapse.T_pre * Δt
	end
	if synapse.post_neuron.spike_train[current_time] == 1
		# Depression due to post-synaptic spike
		synapse.weight -= A_minus * synapse.T_post * Δt
	end

	# Clamp weight within reasonable bounds
	synapse.weight = clamp(synapse.weight, -3.0, 3.0)
end

# STDP update function for all synapses
function synapses_STDP_update!(synapses::Vector{Synapse}, current_time::Int, Δt::Float64)
	for synapse in synapses
		synapse_STDP_update!(synapse, current_time, Δt)
	end
end

# Astrocyte LIM model update function
function astrocyte_LIM_update!(astrocyte::Astrocyte, current_time::Int, u_i::Vector{Float64}, Δt::Float64)
	# Calculate the total spikes from liquid and input neurons at the current time
	liquid_spikes = sum(neuron.spike_train[current_time] for neuron in astrocyte.liquid_neurons)
	input_spikes = sum(u_i .!= 0.0)
	
	# Compute the change in astrocyte activity
	dA_astro_dt = (-astrocyte.A_astro * astrocyte.Γ_astro + astrocyte.w_astro * (liquid_spikes - input_spikes) + astrocyte.b_astro) / astrocyte.τ_astro
	
	# Update the astrocyte's state using Euler integration
	astrocyte.A_astro += dA_astro_dt * Δt
end

# LIM update function for all astrocytes
function astrocytes_LIM_update!(astrocytes::Vector{Astrocyte}, current_time::Int, u_i::Vector{Float64}, Δt::Float64)
	s = []
	for astrocyte in astrocytes
		liquid_spikes = sum(neuron.spike_train[current_time] for neuron in astrocyte.liquid_neurons)
		input_spikes = sum(u_i .!= 0.0)
		push!(s, liquid_spikes - input_spikes)

		astrocyte_LIM_update!(astrocyte, current_time, u_i, Δt)
	end

	println("Astrocyte activity; mean liq-in spike diff: ", mean(s))
end

function simulate!(u_i_f::Function, neurons::Vector{Neuron}, synapses::Vector{Synapse}, astrocytes::Vector{Astrocyte}; duration::Int=100, Δt::Float64=1.0)
	for current_time in 1:duration
		# TODO: 
		# 	Technical:
		#	- 1. Add input adapter, spiking neurons, ouptut point neuron, & inhib neurons/synapses
		#	- 2. Connect spiking neurons (input from input adapter) with synapses to liquid neurons
		#	- 3. Connect liquid neurons with synapses to readout neurons
		# 	Practical:
		# 	- 0. Isolate mutable parts from immutable structures (speed up => simpler job for parallelism)
		# 	- 1. Add multi-processing
		#
		
		u_i = u_i_f(current_time)

		# Update neurons with the LIF model
		neurons_LIF_update!(neurons, current_time, u_i, Δt)
		
		# Update synapses with the STDP model
		synapses_STDP_update!(synapses, current_time, Δt)
		
		# Update astrocytes with the LIM model
		astrocytes_LIM_update!(astrocytes, current_time, u_i, Δt)
	end
end

function Base.show(io::IO, ::MIME"text/plain", n::Vector{Neuron})
    println(io, "Neurons.")
end

function Base.show(io::IO, ::MIME"text/plain", s::Vector{Synapse})
	println(io, "Synapses!")
end

function Base.show(io::IO, ::MIME"text/plain", a::Vector{Astrocyte})
	println(io, "Astrocytes!!")
end

function simulate_w_hist!(hist_dict::Dict, u_i_f::Function, neurons::Vector{Neuron}, synapses::Vector{Synapse}, astrocytes::Vector{Astrocyte}; duration::Int=100, Δt::Float64=1.0)
	neuron_membrane_hist = Matrix{Float64}(undef, length(neurons), duration)
	synapse_weight_hist = Matrix{Float64}(undef, length(synapses), duration)
	astrocyte_A_hist = Matrix{Float64}(undef, length(astrocytes), duration)

	for current_time in 1:duration
		# TODO: 
		# 	Technical:
		#	- 1. Add input adapter, spiking neurons, ouptut point neuron, & inhib neurons/synapses
		#	- 2. Connect spiking neurons (input from input adapter) with synapses to liquid neurons
		#	- 3. Connect liquid neurons with synapses to readout neurons
		# 	Practical:
		# 	- 0. Isolate mutable parts from immutable structures (speed up => simpler job for parallelism)
		# 	- 1. Add multi-processing
		#
		
		println("current_time: ", current_time)

		u_i = u_i_f(current_time)

		# Update neurons with the LIF model
		neurons_LIF_update!(neurons, current_time, u_i, Δt)
		# Update synapses with the STDP model
		synapses_STDP_update!(synapses, current_time, Δt)
		# Update astrocytes with the LIM model
		astrocytes_LIM_update!(astrocytes, current_time, u_i, Δt)
	
		# Record neuron membrane potentials
		for (i, neuron) in enumerate(neurons)
			neuron_membrane_hist[i, current_time] = neuron.membrane_potential
		end
		# Record synapse weights
		for (i, synapse) in enumerate(synapses)
			synapse_weight_hist[i, current_time] = synapse.weight
		end
		# Record astrocyte A_astro
		for (i, astrocyte) in enumerate(astrocytes)
			astrocyte_A_hist[i, current_time] = astrocyte.A_astro
		end
	end

	hist_dict["neuron_membrane_hist"] = hcat(hist_dict["neuron_membrane_hist"], neuron_membrane_hist)
	hist_dict["synapse_weight_hist"] = hcat(hist_dict["synapse_weight_hist"], synapse_weight_hist)
	hist_dict["astrocyte_A_hist"] = hcat(hist_dict["astrocyte_A_hist"], astrocyte_A_hist)
end