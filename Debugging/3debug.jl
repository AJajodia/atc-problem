# imports
using JuMP, GLPK, CSV, DataFrames

# --- Data preprocessing ---

sectors_df = DataFrame(CSV.File("debug_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)

# Lists of airports and sectors as strings
airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)

# Dictionaries for airports info () and sectors capacity data keyed by string
airports = Dict(string.(sectors_df.airport[i]) => [sectors_df[i, col] for col in 6:ncol(sectors_df)] for i in 1:nrow(sectors_df))
sector_capacity = Dict(string.(sectors_df.sector[i]) => sectors_df.sector_capacity[i] for i in 1:nrow(sectors_df))

# Timetable and lookup dictionaries
timetable_df = DataFrame(CSV.File("debug_timetable.csv"))
sector_lookup = Dict(sectors_list[i] => i for i in 1:nrow(sectors_df))
airport_lookup = Dict(sectors_df.airport[i] => i for i in 1:nrow(sectors_df))

# Other data
l = DataFrame(CSV.File("debug_min_times.csv", header = false))
start_df = DataFrame(CSV.File("debug_flight_min_times.csv", header = false))
buffer_time = 4

# Flight paths: rows = steps along path, cols = flights
P = DataFrame(CSV.File("debug_flight_paths.csv", header = false))

# --- Model setup ---

m = Model(GLPK.Optimizer)

F = nrow(timetable_df)      # Number of flights
K = nrow(airports_df)       # Number of airports
J = nrow(sectors_df)        # Number of sectors (all sectors in system)

# N[f] = number of steps (sectors/airports) along flight f's path
N = [sum([P[step, f] != "0" for step in 1:nrow(P)]) for f in 1:ncol(P)]

T = 20  # number of time periods (96 fifteen minutes in 1 day) + buffer (4 time periods)

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
    start_time = Int(start_df[j, f])
    end_time = start_time + buffer_time
    return start_time:end_time
end

function W(f, t, j)
    f = convert(Int, f)
    t = convert(Int, t)
    j = convert(Int, j)

    return w[P[j, f]][f, t]
end
# Declaring variables

w = Dict(sector => [@variable(m, binary = true) for f in 1:F, t in 1:T] for sector in vcat(sectors_list, airports_list))

# Setting the objective

#@objective(m, Min, sum(
#    c[f,1] * (sum(t * (W(f,t,1) - W(f,t-1,1)) for t in Tjf(f,1)) - timetable_df[f, :depart_time]) +
#    c[f,2] * (sum(t * (W(f,t,N[f]) - W(f,t-1,N[f])) for t in Tjf(f,N[f])) - timetable_df[f, :arrival_time])
#    for f in 1:F
#))
#@objective(m, Min, sum(((c[f,1]-c[f,2]) * sum(t*(W(f, t, 1) - W(f, t-1, 1)) for t in Tjf(f, 1))) + (c[f, 2] * sum(t*(W(f, t, N[f]) - W(f, t-1, N[f])) for t in Tjf(f, N[f]))) for f in 1:F))
@objective(m, Min, sum(
    c[f,1] * sum(t * (W(f, t, 1) - W(f, t-1, 1)) for t in Tjf(f, 1) if t > 1) -
    c[f,1] * start_df[1, f] +
    c[f,2] * sum(t * (W(f, t, N[f]) - W(f, t-1, N[f])) for t in Tjf(f, N[f]) if t > 1) -
    c[f,2] * start_df[N[f], f]
    for f in 1:F
        ))
#@objective(m, Min, sum(
#    c[f,1] * sum(t * (W(f, t, 1) - W(f, t-1, 1)) for t in Tjf(f, 1) if t > 1) -
#    c[f,1] * timetable_df[f, :depart_time] +
#    c[f,2] * sum(t * (W(f, t, N[f]) - W(f, t-1, N[f])) for t in Tjf(f, N[f]) if t > 1) -
#    c[f,2] * timetable_df[f, :arrival_time]
#    for f in 1:F
#))

println("Objective good")
# Adding constraints

# airport and sector capacity constraints
for k in 1:K, t in 2:T
    @constraint(m, sum(W(f, t, 1) - W(f, t-1, 1) for f in 1:F) <= D(k, t))
    @constraint(m, sum(W(f, t, N[f]) - W(f, t-1, N[f]) for f in 1:F) <= A(k, t))
end
for j in 1:J, t in 2:T
    @constraint(m, sum(W(f, t, j) - W(f, t, j+1) for f in 1:F if j < N[f]) <= S(j, t))
end

# connectivity constraints
for f in 1:F
    for j in 1:N[f]-1
        # didn't include connecting flights
        for t in Tjf(f, j)
            @constraint(m, W(f, t + l[j, f], j + 1) - W(f, t, j) <= 0)
        end
    end

    for j in 1:N[f]
        for t in Tjf(f, j)
            @constraint(m, W(f, t, j) - W(f, t-1, j) >= 0)
        end
    end
end

for f in 1:F
    @constraint(m, W(f, Tjf(f, N[f])[end], N[f]) == 1)
end

for f in 1:F
    for t in 2:T
        for j in 1:N[f]
            if t < Tjf(f, 1)[1]
                @constraint(m, W(f, t, j) == 0)
            end
        end
    end
end

for f in 1:F
    #@constraint(m, sum(t * (W(f,t,1) - W(f,t-1,1)) for t in Tjf(f,1)) >= timetable_df[f, :depart_time])
    @constraint(m, sum(t * (W(f,t,N[f]) - W(f,t-1,N[f])) for t in Tjf(f,N[f])) >= start_df[N[f], f])
end

# Solving the optimization problem
JuMP.optimize!(m)

# Print the information about the optimum.
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

println("\nDelay Report:")
for f in 1:F
    # Compute actual departure time
    dep_time = sum(t * (value(W(f, t, 1)) - value(W(f, t - 1, 1))) for t in Tjf(f, 1) if t > 1)
    sch_dep = timetable_df[f, :depart_time]
    
    # Compute actual arrival time
    arr_time = sum(t * (value(W(f, t, N[f])) - value(W(f, t - 1, N[f]))) for t in Tjf(f, N[f]) if t > 1)
    sch_arr = timetable_df[f, :arrival_time]
    
    # Delay amounts
    dep_delay = max(0, dep_time - sch_dep)
    arr_delay = max(0, arr_time - sch_arr)
    
    if dep_delay > 0 || arr_delay > 0
        println("Flight $f delayed:")
        if dep_delay > 0
            println("  Departure Delay: $dep_delay (Scheduled: $sch_dep, Actual: $dep_time)")
        end
        if arr_delay > 0
            println("  Arrival Delay: $arr_delay (Scheduled: $sch_arr, Actual: $arr_time)")
        end
    end
end