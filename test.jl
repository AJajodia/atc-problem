# Imports
using JuMP, GLPK, CSV, DataFrames

# --- Data preprocessing ---

sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)

airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)

# Dictionary of airport data
airports = Dict(string(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))
sector_capacity = Dict(string(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

# Timetable and lookup
timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))
sector_lookup = Dict(sectors_list[i] => i for i in 1:nrow(sectors_df))
airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))

l = DataFrame(CSV.File("min_times_anu.csv", header = false))
start_df = DataFrame(CSV.File("flight_min_times_anu.csv", header = false))
buffer_time = 4
P = DataFrame(CSV.File("flight_paths_anu.csv", header = false))

# --- Model setup ---
m = Model(GLPK.Optimizer)

F = nrow(timetable_df)
K = nrow(airports_df)
J = nrow(sectors_df)
N = [sum(P[!, f] .!= "0") for f in 1:ncol(P)]
T = 200  # Time horizon

# Cost matrix
c = [10 100 for _ in 1:F]  # Ground and air costs

# --- Capacity functions ---

function D(k, t)
    airport = airports_list[k]
    return airports[airport][7]
end

function A(k, t)
    airport = airports_list[k]
    return airports[airport][8]
end

function S(j, t)
    sector = sectors_list[j]
    return sector_capacity[sector]
end

function Tjf(f, j)
    start_time = Int(start_df[j, f])
    end_time = min(start_time + buffer_time, T)
    return start_time:end_time
end

# --- Variable w[f, t, j] for each (flight, time, step in path) ---
w = Dict(sector => [@variable(m, Bin) for f in 1:F, t in 1:T] for sector in vcat(sectors_list, airports_list))

# --- Helper function W ---
function W(f, t, j)
    step_sector = P[j, f]
    return w[step_sector][f, t]
end

# --- Objective Function ---
@objective(m, Min, sum(
    (c[f,1] - c[f,2]) * sum(t * (W(f, t, 1) - (t > 1 ? W(f, t - 1, 1) : 0)) for t in Tjf(f, 1)) +
    c[f,2] * sum(t * (W(f, t, N[f]) - (t > 1 ? W(f, t - 1, N[f]) : 0)) for t in Tjf(f, N[f]))
    for f in 1:F
))

println("Objective defined.")

# --- Constraints ---

# Capacity constraints (Airports)
for k in 1:K, t in 2:T
    airport = airports_list[k]
    @constraint(m, sum(W(f, t, 1) - W(f, t - 1, 1) for f in 1:F if P[1, f] == airport) <= D(k, t))
    @constraint(m, sum(W(f, t, N[f]) - W(f, t - 1, N[f]) for f in 1:F if P[N[f], f] == airport) <= A(k, t))
end

# Capacity constraints (Sectors)
for j in 1:J, t in 2:T
    sector = sectors_list[j]
    @constraint(m, sum(W(f, t, s) - W(f, t, s + 1) for f in 1:F, s in 1:(N[f] - 1) if P[s, f] == sector && s + 1 <= N[f]) <= S(j, t))
end

# Connectivity constraints
for f in 1:F
    for j in 1:N[f] - 1
        for t in Tjf(f, j)
            arr_time = t + Int(l[j, f])
            if arr_time <= T
                @constraint(m, W(f, arr_time, j + 1) - W(f, t, j) <= 0)
            end
        end
    end
    for j in 1:N[f]
        for t in Tjf(f, j)
            if t > 1
                @constraint(m, W(f, t, j) - W(f, t - 1, j) >= 0)
            end
        end
    end
end

# Arrival must happen by end
for f in 1:F
    @constraint(m, W(f, Tjf(f, N[f])[end], N[f]) == 1)
end

# Pre-start times must be zero
for f in 1:F
    for t in 2:T
        if t < Tjf(f, 1)[1]
            for j in 1:N[f]
                @constraint(m, W(f, t, j) == 0)
            end
        end
    end
end

# Minimum arrival constraint
for f in 1:F
    @constraint(m, sum(t * (W(f, t, N[f]) - (t > 1 ? W(f, t - 1, N[f]) : 0)) for t in Tjf(f, N[f])) >= start_df[N[f], f])
end

# --- Solve ---
optimize!(m)

# --- Output ---
println("Total Cost: ", objective_value(m))
for sector in keys(w)
    println("Sector/Airport: ", sector)
    for f in 1:F
        for t in 1:T
            val = value(w[sector][f, t])
            if !isnothing(val) && val > 0.5
                println("  Flight $f, Time $t: $val")
            end
        end
    end
end
