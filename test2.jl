using JuMP, GLPK, CSV, DataFrames

# Data Preprocessing
sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = dropmissing(sectors_df)
airports_list = string.(airports_df.airport)
airports = Dict(string(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))
sectors = Dict(string(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))
sectors_list = string.(sectors_df.sector)
timetable_df = DataFrame(CSV.File("mariah_timetable.csv"))
l = DataFrame(CSV.File("min_times_anu.csv", header=false))
start_df = DataFrame(CSV.File("flight_min_times_anu.csv", header=false))
P = DataFrame(CSV.File("flight_paths_anu.csv", header=false))

buffer_time = 1
T = 100
F = nrow(timetable_df)
K = length(airports_list)
J = length(sectors_list)
N = [sum(P[j, i] != "0" for j in 1:nrow(P)) for i in 1:ncol(P)]
nodes = unique(vcat(sectors_list, airports_list))

# Cost coefficients
c = fill([10, 100], F)

# Time window function
function Tjf(f, j)
    start_time = Int(start_df[j, f])
    return start_time:T
end

# Functions for sector, airport capacity
function D(k, t)
    airport = airports_list[k]
    return airports[airport][8]  # assume 9th column in CSV
end

function A(k, t)
    airport = airports_list[k]
    return airports[airport][9]  # assume 10th column in CSV
end

function S(j, t)
    sector = sectors_list[j]
    return sectors[sector]
end

# Optimization Model
m = Model(GLPK.Optimizer)

# Decision variables
w = Dict(node => @variable(m, [1:F, 1:T], Bin) for node in nodes)

# Accessor for w based on flight path
function W(f, t, j)
    node = string(P[j, f])
    return node != "0" ? w[node][f, t] : 0
end

# Objective function
#@objective(m, Min, sum(
    #(c[f][1] - c[f][2]) * sum(t * (W(f, t, 1) - W(f, t - 1, 1)) for t in Tjf(f, 1) if t > 1) +
    #c[f][2] * sum(t * (W(f, t, N[f]) - W(f, t - 1, N[f])) for t in Tjf(f, N[f]) if t > 1)
    #for f in 1:F
#))
@objective(m, Min, sum(sum(W(f, t, j) for t in 1:T) for f in 1:F, j in 1:N[f]))

println("Objective function constructed.")

# Capacity constraints (adjusted safely)
for k in 1:K, t in 2:T
    @constraint(m, sum(W(f, t, 1) - W(f, t - 1, 1) for f in 1:F) <= D(k, t))
    @constraint(m, sum(W(f, t, N[f]) - W(f, t - 1, N[f]) for f in 1:F) <= A(k, t))
end

for j in 1:J, t in 2:T
    @constraint(m, sum(W(f, t, j) - W(f, t, j + 1) for f in 1:F if j + 1 <= N[f]) <= S(j, t))
end

# Connectivity constraints
for f in 1:F
    for j in 1:N[f]-1
        for t in Tjf(f, j)
            next_time = t + Int(l[j, f])
            if next_time <= T
                @constraint(m, W(f, next_time, j + 1) - W(f, t, j) <= 0)
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

# Ensure each flight reaches its final node
for f in 1:F
    @constraint(m, W(f, Tjf(f, N[f])[end], N[f]) == 1)
end

# Zero activation before earliest allowed time
for f in 1:F
    earliest = Tjf(f, 1)[1]
    for t in 1:earliest-1, j in 1:N[f]
        @constraint(m, W(f, t, j) == 0)
    end
end

# Solve
optimize!(m)

# Output
println("Total Cost: ", objective_value(m))