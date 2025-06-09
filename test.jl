# imports
using JuMP, GLPK, CSV, DataFrames

# --- Data preprocessing ---

sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)

# Lists of airports and sectors as strings
airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)

# Dictionaries for airports info () and sectors capacity data keyed by string
airports = Dict(string.(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))
sector_capacity = Dict(string.(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

# Timetable and lookup dictionaries
timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))
sector_lookup = Dict(sectors_list[i] => i for i in 1:nrow(sectors_df))
airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))

# Other data
l = DataFrame(CSV.File("min_times_anu.csv", header = false))
start_df = DataFrame(CSV.File("flight_min_times_anu.csv", header = false))
buffer_time = 1

# Flight paths: rows = steps along path, cols = flights
P = DataFrame(CSV.File("flight_paths_anu.csv", header = false))

# --- Model setup ---

m = Model(GLPK.Optimizer)

F = nrow(timetable_df)      # Number of flights
K = nrow(airports_df)       # Number of airports
J = nrow(sectors_df)        # Number of sectors (all sectors in system)

# N[f] = number of steps (sectors/airports) along flight f's path
N = [sum([P[step, f] != "0" for step in 1:nrow(P)]) for f in 1:ncol(P)]

T = 96  # number of time periods (96 fifteen minutes in 1 day)

# Cost matrix: rows = flights, columns = [ground cost, air cost]
c = zeros(F, 2)
for f in 1:F
    c[f, 1] = 10    # ground holding cost
    c[f, 2] = 100   # air holding cost
end

# --- Capacity functions ---

function D(k, t)
    # Departure capacity for airport k at time t
    airport = airports_list[k]
    airports[airport][7]
end

function A(k, t)
    airport = airports_list[k]
    return airports[airport][8]
end

function S(j, t)
    sector = sectors_list[j]
    return sector_capacity[sector]
end

# --- Time windows for flights at each step along their path ---

function Tjf(f, step)
    # Time window for flight f at path step
    start_time = start_df[step, f]
    end_time = start_time + buffer_time
    return start_time:end_time
end

# --- Decision variables ---

# Binary variable w[loc][flight, time]: 1 if flight has arrived at loc by time t
all_locations = union(sectors_list, airports_list)
w = Dict{String, Array{VariableRef, 2}}()
for loc in all_locations
    w[loc] = @variable(m, [1:F, 1:T], Bin)
end

# --- Helper function to access w variables ---

function W(f, t, step)
    f = convert(Int, f)
    t = convert(Int, t)
    step = convert(Int, step)
    # Returns binary variable indicating flight f arrived at location at path step by time t
    loc = P[step, f]
    if loc == "0"
        return 0  # no location at this step => no presence
    else
        return w[loc][f, t]
    end
end

# --- Objective function: minimize total cost ---

@objective(m, Min, sum(
    # Ground holding cost: difference between actual and scheduled departure time
    c[f,1] * (sum(t * (W(f,t,1) - (t > 1 ? W(f,t-1,1) : 0)) for t in Tjf(f,1)) - timetable_df[f, :depart_time]) +

    # Air holding cost: difference between actual and scheduled arrival time
    c[f,2] * (sum(t * (W(f,t,N[f]) - (t > 1 ? W(f,t-1,N[f]) : 0)) for t in Tjf(f,N[f])) - timetable_df[f, :arrival_time])
    for f in 1:F
))

# --- Constraints ---

# 1) Departure capacity constraints at airports (step 1 locations)
for k in 1:K, t in 2:T
    @constraint(m, sum(W(f, t, 1) - W(f, t-1, 1) for f in 1:F) <= D(k, t))
end

# 2) Arrival capacity constraints at airports (last step locations)
for k in 1:K, t in 2:T
    @constraint(m, sum(W(f, t, N[f]) - W(f, t-1, N[f]) for f in 1:F) <= A(k, t))
end

# 3) Sector capacity constraints for all intermediate sectors along flight paths
for t in 2:T
    for f in 1:F
        for step in 1:N[f]
            if step < N[f]
                loc = P[step, f]
                cap = S(loc, t)
                @constraint(m, sum(W(f, t, step) - W(f, t, step + 1) for f in 1:F if P[step, f] != "0") <= cap)
            end
        end
    end
end

# 4) Connectivity constraints between steps (flight flow continuity)
for f in 1:F
    for step in 1:N[f]-1
        for t in Tjf(f, step)
            travel_time = l[step, f]
            if t + travel_time <= T
                @constraint(m, W(f, t + travel_time, step + 1) - W(f, t, step) <= 0)
            end
        end
    end
end

# 5) Monotonicity constraints: W non-decreasing over time
for f in 1:F
    for step in 1:N[f]
        times = collect(Tjf(f, step))
        for i in 2:length(times)
            t = times[i]
            prev_t = times[i-1]
            @constraint(m, W(f, t, step) - W(f, prev_t, step) >= 0)
        end
    end
end

# 6) Fix W variables to 1 at last time in time window (must arrive by last feasible time)
for f in 1:F
    for step in 1:N[f]
        last_t = maximum(Tjf(f, step))
        @constraint(m, W(f, last_t, step) == 1)
    end
end

# --- Optimize ---

optimize!(m)

# --- Output ---

if termination_status(m) == MOI.OPTIMAL
    println("Optimal total cost: ", objective_value(m))
else
    println("No optimal solution found.")
end