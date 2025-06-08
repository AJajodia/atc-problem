using JuMP, GLPK, CSV, DataFrames

# Load data
sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = dropmissing(sectors_df)  # remove rows with NA airports

timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))
min_times_df = DataFrame(CSV.File("min_times_anu.csv", header=false))
start_times_df = DataFrame(CSV.File("flight_min_times_anu.csv", header=false))
paths_df = DataFrame(CSV.File("flight_paths_anu.csv", header=false))

# Extract constants
F = nrow(timetable_df)  # number of flights
J = nrow(sectors_df)    # number of sectors (includes airports)

T = 100  # planning horizon
buffer_time = 1

# Create lists/dictionaries for easy access
# Sector capacities (indexed by sector ID as string)
sector_caps = Dict(string(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:J)

# Airport capacity lookup by airport string, using columns 8 (depart_capacity) and 9 (arrival_capacity)
# Assumes columns 8 and 9 are depart_capacity and arrival_capacity (verify!)
airport_depart_caps = Dict(string(sectors_df.airport[i]) => sectors_df.depart_capacity[i] for i in 1:J if !ismissing(sectors_df.airport[i]))
airport_arrive_caps = Dict(string(sectors_df.airport[i]) => sectors_df.arrival_capacity[i] for i in 1:J if !ismissing(sectors_df.airport[i]))

# List of airports from non-missing rows
airports_list = [string(row.airport) for row in eachrow(airports_df)]

# Preprocess paths_df:
# Convert all entries to String and keep track of "0" meaning no sector
paths = Array{String}(undef, size(paths_df)...)
for i in 1:size(paths_df,1), j in 1:size(paths_df,2)
    val = paths_df[i,j]
    paths[i,j] = string(val)
end

# Preprocess start_times_df and min_times_df as Float64 arrays (sector x flight)
start_times = Matrix{Float64}(start_times_df)
min_times = Matrix{Float64}(min_times_df)

# Cost arrays (ground and air)
ground_cost = 10
air_cost = 100

# Model
model = Model(GLPK.Optimizer)

# Variables:
# For each sector/airport string in the paths columns, for each flight, for each time 1:T,
# create binary variables W indicating if flight f is in sector/airport s at time t
# Because paths contain a mix of airports and sectors, we collect all unique nodes first
unique_nodes = unique(vec(paths))
unique_nodes = filter(n -> n != "0", unique_nodes)  # exclude "0"

# Build variable dict: w[node][flight, time]
w = Dict{String, Matrix{VariableRef}}()
for node in unique_nodes
    w[node] = @variable(model, [1:F, 1:T], Bin)
end

# Helper function to get sector capacity or airport capacity by node name and type
function capacity(node::String, t::Int)
    if haskey(sector_caps, node)
        return sector_caps[node]
    elseif haskey(airport_depart_caps, node)
        return max(airport_depart_caps[node], airport_arrive_caps[node])  # take max to be safe
    else
        return 0  # unknown node, zero capacity
    end
end

# N_f = number of sectors/airports visited by flight f (length of non-"0" in paths)
N_f = [count(x -> x != "0", paths[:, f]) for f in 1:F]

# Helper: for flight f and step j, get node (sector or airport)
function node_for(f, j)
    return paths[j, f]
end

# Helper: Time window for flight f at step j (start time to start time + buffer)
function time_window(f, j)
    st = Int(round(start_times[j, f]))
    return st:(st+buffer_time)
end

# Objective: minimize total cost
@objective(model, Min,
    sum(
        # cost for ground time at first node
        (ground_cost) * sum(t * (w[node_for(f, 1)][f, t] - (t > 1 ? w[node_for(f, 1)][f, t-1] : 0)) for t in time_window(f, 1))
        +
        # cost for air time at last node
        (air_cost) * sum(t * (w[node_for(f, N_f[f])][f, t] - (t > 1 ? w[node_for(f, N_f[f])][f, t-1] : 0)) for t in time_window(f, N_f[f]))
        for f in 1:F
    )
)

# Constraints

# 1) Capacity constraints at airports (depart & arrival)
for t in 2:T, airport in airports_list
    if haskey(airport_depart_caps, airport)
        @constraint(model,
            sum(
                w[airport][f, t] - w[airport][f, t-1]
                for f in 1:F if airport == node_for(f, 1)
            ) <= airport_depart_caps[airport]
        )
    end
    if haskey(airport_arrive_caps, airport)
        @constraint(model,
            sum(
                w[airport][f, t] - w[airport][f, t-1]
                for f in 1:F if airport == node_for(f, N_f[f])
            ) <= airport_arrive_caps[airport]
        )
    end
end

# 2) Capacity constraints at sectors (intermediate nodes)
for t in 2:T
    for sector in keys(sector_caps)
        # sum over all flights and all steps where sector == node_for(f,j)
        @constraint(model,
            sum(
                # Only consider steps j where node == sector and j < N_f[f]
                w[sector][f, t] - w[sector][f, t-1]
                for f in 1:F, j in 1:(N_f[f]-1) if node_for(f, j) == sector
            ) <= sector_caps[sector]
        )
    end
end

# 3) Connectivity constraints: a flight cannot be in step j+1 at time t + min_time without being in step j at time t
for f in 1:F
    for j in 1:(N_f[f]-1)
        Δt = Int(round(min_times[j, f]))
        for t in time_window(f, j)
            if t + Δt <= T
                @constraint(model,
                    w[node_for(f, j+1)][f, t + Δt] - w[node_for(f, j)][f, t] <= 0
                )
            end
        end
    end
end

# 4) Monotonicity constraints: once in node at time t, must have been there at t-1 or just arrived
for f in 1:F
    for j in 1:N_f[f]
        for t in time_window(f, j)
            if t > 1
                @constraint(model,
                    w[node_for(f, j)][f, t] - w[node_for(f, j)][f, t-1] >= 0
                )
            end
        end
    end
end

# Optimize
optimize!(model)

# Results summary
println("Objective value (total cost): ", objective_value(model))