include("reservoir-components.jl")
# include("read_in.jl")
# include("read_out.jl")
include("util.jl")

struct LiquidStateMachine
    # spk_neurons::Vector{AbstractNeuron}
    # readin_synapses::Vector{Synapse}
    liq_neurons::Vector{AbstractNeuron}
    liq_synapses::Array{Synapse}
    liq_astrocytes::Array{Astrocyte}
    # readout_synapses::Vector{Synapse}
    # readout_neurons::Vector{AbstractNeuron}

    astro_t_avg::Int

    reservoir_hist::Dict{String, Matrix{Float64}}

    u_i_t_stim::Function
    u_i_t_rest::Function

    sim_length::Int

    function LiquidStateMachine(;num_spk_neurons::Int=80, num_liq_neurons::Int=1000, grid_type::String="cube", simulation_length::Int=125)
        if grid_type == "hex-prism"
            base_hex_grid_positions = generate_hexagonal_prism_grid(3, 6, 1.0)  # Three-layer hex grid
            grid = tile_hexagonal_prism_grid(base_hex_grid_positions, (6, 6), 1.0)  # 3x3 tiling of the hex grid
        # elseif grid_type == "tri-prism"
        #     base_tri_grid_positions = generate_triangular_prism_grid(10, 7, 1.0)  # Three-layer triangle grid
        #     grid = tile_triangular_prism_grid(base_tri_grid_positions, (7, 7), 1.0)  # 3x3 tiling of the triangle grid
        elseif grid_type == "cube"
            grid = generate_cubic_grid((10, 10, 10), 1.0)  # 10x10x10 grid with 1.0 unit spacing
        # elseif grid_type == "truncated_octahedron"
        #     grid_size = (3, 3, 3)  # Define the size of the grid
        #     spacing = 2.0          # Define the spacing between the centers
        #     grid = generate_truncated_octahedron_grid(grid_size, spacing)
        else
            error("Invalid grid type!")
        end

        liq_neurons = initialize_neurons_on_grid(grid, num_liq_neurons, simulation_length=simulation_length)
        liq_synapses = initialize_synapses(liq_neurons, simulation_length=simulation_length)
        num_liq_astrocytes=1500
        # determine number of astro based on num of synapses
        liq_astrocytes = initialize_astrocytes(num_liq_astrocytes, liq_synapses)

        freq = 500
        astro_t_avg = 10 # too small -> A_astro jumpy; too large -> wrong BF ratio approx

        reservoir_hist = Dict(
            "neuron_membrane_hist" => Matrix{Float64}(undef, num_liq_neurons, 0),
            "synapse_weight_hist" => Matrix{Float64}(undef, length(liq_synapses), 0),
            "astrocyte_A_hist" => Matrix{Float64}(undef, num_liq_astrocytes, 0),
        )

        u_i_t_stim = coin_factory(0.95, num_spk_neurons)
        u_i_t_rest = coin_factory(0.1, num_spk_neurons)
        # u_i_t_stim = freq_factory(num_spk_neurons, freq=freq)
        # u_i_t_rest = freq_factory(num_spk_neurons, freq=1)
        

        new(
            liq_neurons, 
            liq_synapses, 
            liq_astrocytes,
            astro_t_avg, 

            reservoir_hist,

            u_i_t_stim,
            u_i_t_rest,
            simulation_length
        )
    end
end

function reset_hist!(lsm::LiquidStateMachine)
    lsm.reservoir_hist["neuron_membrane_hist"] = Matrix{Float64}(undef, length(lsm.liq_neurons), 0)
    lsm.reservoir_hist["synapse_weight_hist"] = Matrix{Float64}(undef, length(lsm.liq_synapses), 0)
    lsm.reservoir_hist["astrocyte_A_hist"] = Matrix{Float64}(undef, length(lsm.liq_astrocytes), 0)
end

function simulate!(lsm::LiquidStateMachine; u_i_f=nothing, Δt::Float64=1.0)
    time_offset = length(lsm.liq_neurons[1].spike_train)

    for local_time in 1:lsm.sim_length
        global_time = local_time + time_offset

        if isnothing(u_i_f)
            u_i_f = lsm.u_i_t_rest
        end   
        u_i = u_i_f(global_time)
        # when read_in is implemented, u_i_f => u_i will be the stimulus passed to readin
        
		neurons_LIF_update!(lsm.liq_neurons, global_time, u_i, Δt)
		synapses_STDP_update!(lsm.liq_synapses, global_time, Δt)
        ts = max(global_time-lsm.astro_t_avg+1, 1):global_time
        u_i_ts = hcat([u_i_f(t) for t in ts]...)
        astrocytes_LIM_update!(lsm.liq_astrocytes, global_time, u_i_ts, Δt)
	end
end

function simulate_w_hist!(lsm::LiquidStateMachine; u_i_f=nothing, Δt::Float64=1.0)
	neuron_membrane_hist = Matrix{Float64}(undef, length(lsm.liq_neurons), lsm.sim_length)
	synapse_weight_hist = Matrix{Float64}(undef, length(lsm.liq_synapses), lsm.sim_length)
	astrocyte_A_hist = Matrix{Float64}(undef, length(lsm.liq_astrocytes), lsm.sim_length)

    time_offset = length(lsm.liq_neurons[1].spike_train)

	for local_time in 1:lsm.sim_length
        global_time = local_time + time_offset

		println("current_time: ", global_time)

        if isnothing(u_i_f)
            u_i_f = lsm.u_i_t_rest
        end   
        u_i = u_i_f(global_time)

		neurons_LIF_update!(lsm.liq_neurons, global_time, u_i, Δt)
		synapses_STDP_update!(lsm.liq_synapses, global_time, Δt)
		ts = max(global_time-lsm.astro_t_avg+1, 1):global_time
        u_i_ts = hcat([u_i_f(t) for t in ts]...)
        astrocytes_LIM_update!(lsm.liq_astrocytes, global_time, u_i_ts, Δt)
	
		# Record neuron membrane potentials
		for (i, neuron) in enumerate(lsm.liq_neurons)
			neuron_membrane_hist[i, local_time] = neuron.membrane_potential
		end
		# Record synapse weights
		for (i, synapse) in enumerate(lsm.liq_synapses)
			synapse_weight_hist[i, local_time] = synapse.weight
		end
		# Record astrocyte A_astro
		for (i, astrocyte) in enumerate(lsm.liq_astrocytes)
			astrocyte_A_hist[i, local_time] = astrocyte.A_astro
		end
	end

	lsm.reservoir_hist["neuron_membrane_hist"] = hcat(lsm.reservoir_hist["neuron_membrane_hist"], neuron_membrane_hist)
	lsm.reservoir_hist["synapse_weight_hist"] = hcat(lsm.reservoir_hist["synapse_weight_hist"], synapse_weight_hist)
	lsm.reservoir_hist["astrocyte_A_hist"] = hcat(lsm.reservoir_hist["astrocyte_A_hist"], astrocyte_A_hist)
end

# function (lsm::LiquidStateMachine)(input::Vector{Float64})

#     # h1 = lsm.read_in_connections(input)

#     h2 = simulate!(lsm, input)

#     # output = lsm.read_out_connections(h2)

#     return h2
# end

function Base.show(io::IO, ::MIME"text/plain", a::LiquidStateMachine)
    println(io, "Liquid State Machine assembled!!!!")
end