# imports
using JuMP, GLPK, CSV, DataFrames

# --- Data preprocessing ---

sectors_df = DataFrame(CSV.File("mariah_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)

# Lists of airports and sectors as strings
airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)
all_sectors_list = vcat(string.(sectors_df.sector), airports_list)

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
for col in names(start_df)
    try
        start_df[!, col] = Int.(start_df[!, col])  # convert whole column to Int vector
    catch
        # If conversion fails (e.g. for non-numeric columns), just ignore
        println("Skipping column $col (non-integer)")
    end
end
for col in names(l)
    l[!, col] = Int.(l[!, col])
end
buffer_time = 4

# Flight paths: rows = steps along path, cols = flights
P = DataFrame(CSV.File("flight_paths_anu.csv", header = false))

# --- Model setup ---

m = Model(GLPK.Optimizer)

F = nrow(timetable_df)      # Number of flights
K = nrow(airports_df)       # Number of airports
J = length(all_sectors_list)        # Number of sectors (all sectors in system)

# N[f] = number of steps (sectors/airports) along flight f's path
N = [sum([P[step, f] != "0" for step in 1:nrow(P)]) for f in 1:ncol(P)]

T = 200  # number of time periods (96 fifteen minutes in 1 day) + buffer (4 time periods)

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

function Tjf(f, j)
    start_time = Int.(start_df[j, f])
    end_time = start_time + buffer_time
    return start_time:end_time
end

function W(f, t, j)
    f = convert(Int, f)
    t = convert(Int, t)
    j = convert(Int, j)

    return value(w[f, t, j])
end

# Declaring variables
@variable(m, w[1:F, 1:T, 1:J], Bin)

# Setting the objective

#@objective(m, Min, sum(
#    c[f,1] * (sum(t * (W(f,t,1) - W(f,t-1,1)) for t in Tjf(f,1)) - timetable_df[f, :depart_time]) +
#    c[f,2] * (sum(t * (W(f,t,N[f]) - W(f,t-1,N[f])) for t in Tjf(f,N[f])) - timetable_df[f, :arrival_time])
#    for f in 1:F
#))
@objective(m, Min, sum(((c[f,1]-c[f,2]) * sum(t*(w[f, t, 1] - w[f, t-1, 1]) for t in (Tjf(f, 1) .+1) )) + (c[f, 2] * sum(t*(w[f, t, N[f]] - w[f, t-1, N[f]]) for t in (Tjf(f, N[f]) .+1) )) for f in 1:F))


println("Objective good")
# Adding constraints

# airport and sector capacity constraints
for k in 1:K, t in 2:T
    @constraint(m, sum(w[f, t, 1] - w[f, t-1, 1] for f in 1:F) <= D(k, t))
    @constraint(m, sum(w[f, t, N[f]] - w[f, t-1, N[f]] for f in 1:F) <= A(k, t))
end
for j in 1:(J-K), t in 2:T
    @constraint(m, sum(w[f, t, j] - w[f, t, j+1] for f in 1:F if j < N[f]) <= S(j, t))
end

# connectivity constraints
for f in 1:F
    for j in 1:N[f]-1
        # didn't include connecting flights
        for t in Tjf(f, j)
            @constraint(m, w[f, t + l[j, f], j + 1] - w[f, t, j] <= 0)
        end
    end

    for j in 1:N[f]
        for t in 2:T
            @constraint(m, w[f, t, j] >= w[f, t - 1, j])
        end
    end
end

for f in 1:F
    @constraint(m, w[f, Tjf(f, N[f])[end], N[f]] == 1)
    @constraint(m, w[f, Tjf(f, 1)[end], 1] == 1)
end

for f in 1:F
    for t in 2:T
        for j in 1:N[f]
            if t < Tjf(f, 1)[1]
                @constraint(m, w[f, t, j] == 0)
            end
        end
    end
end

for f in 1:F
    #@constraint(m, sum(t * (W(f,t,1) - W(f,t-1,1)) for t in Tjf(f,1)) >= timetable_df[f, :depart_time])
    @constraint(m, sum(t * (w[f,t,N[f]] - w[f,t-1,N[f]]) for t in Tjf(f,N[f])) >= start_df[N[f], f])
end

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
println("Total Cost: ", objective_value(m))

for f in 1:4
    println("Flight ", f, ":")
    for j in 1:N[f]
        seg = P[j, f]
        if seg == "0"
            continue
        end
        for t in Tjf(f, j)
            println("w[$f, $t, $j] = ", W(f, t, j))
            #println("w[$f, $t, $j] = ", value(w[f, t, j]))
        end
    end
end

#println(sum(((5-10) * sum(t*(W(f, t, 1) - W(f, t-1, 1)) for t in Tjf(f, 1))) + (c[f, 2] * sum(t*(W(f, t, N[f]) - W(f, t-1, N[f])) for t in Tjf(f, N[f]))) for f in 1:F))
