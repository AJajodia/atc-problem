using JuMP
using GLPK

sectors_df = DataFrame(CSV.File("debug_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)
min_times_df = DataFrame(CSV.File("debug_flight_min_times.csv", header = false))

all_sectors_list = vcat(string.(sectors_df.sector), string.(airports_df.airport))

flight_paths = DataFrame(CSV.File("debug_flight_paths.csv", header = false)) #all strings, 
                                                                            #rows = steps along path, cols = flights

# Initialize the model
model = Model(GLPK.Optimizer)

# === INPUT DATA STRUCTURES (to be filled with real data) ===

F = 1:ncol(min_times_df)            # Flights
K = 1:nrow(airports_df)             # Airports
J = 1:length(all_sectors_list)      # Sectors
T = 1:15                            # Time periods

P = Dict(f => flight_paths[!, f] for f in 1:F)  
# P[f] = [sector_1, ..., sector_Nf] including airports,

N = Dict(f => sum([P[f][step] != "0" for step in 1:nrow(flight_paths)]) for f in 1:F)   
# N[f] = length(P[f])

df = Dict(f => min_times_df[1, f] for f in F)         # df[f] = Scheduled departure time
rf = Dict(f => min_times_df[N[f], f] for f in F)      # Scheduled arrival time
#sf = Dict{Int, Int}()         # Turnaround time

cg = Dict(f => 10 for f in F)     # Ground delay cost, $10 for each flight
ca = Dict(f => 100 for f in F)     # Air delay cost, $100 for each flight

airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)
Dkt = Dict((k, t) => sectors_df[1, :depart_capacity] for k in airports_list, t in T)  
# Departure capacities D[k,t] at airport k = "A" at time t
Akt = Dict((k,t) => sectors_df[1, :arrival_capacity] for k in airports_list, t in T)  
# Arrival capacities A[k,t] at airport k = "A" at time t
Sjt = Dict{Tuple{Int, Int}, Int}()  # Sector capacities

lfj = Dict{Tuple{Int, Int}, Int}()  # Minimum time in sector j by flight f

Tf = Dict{Tuple{Int, Int}, Vector{Int}}()  # T^j_f: allowed arrival times at sector j for flight f
Tmin = Dict{Tuple{Int, Int}, Int}()
Tmax = Dict{Tuple{Int, Int}, Int}()

C = Vector{Tuple{Int, Int}}()  # Set of (f, f*) aircraft connections

# === VARIABLES ===

@variable(model, w[f in F, j in P[f], t in Tf[(f, j)]], Bin)

# === DERIVED VARIABLES ===

@expression(model, u[f in F, j in P[f], t in Tf[(f, j)]],
    t > Tmin[(f, j)] ? w[f, j, t] - w[f, j, t - 1] : w[f, j, t])

# === OBJECTIVE FUNCTION ===

@expression(model, g[f in F],
    sum(t * u[f, P[f][1], t] for t in Tf[(f, P[f][1])]) - df[f])

@expression(model, a[f in F],
    sum(t * u[f, P[f][end], t] for t in Tf[(f, P[f][end])]) - rf[f] - g[f])

@objective(model, Min,
    sum(cg[f] * g[f] + ca[f] * a[f] for f in F))

# === CONSTRAINTS ===

# (1) Departure Capacity
for k in K, t in T
    @constraint(model,
        sum((w[f, k, t] - w[f, k, t - 1])
            for f in F if P[f][1] == k && t in Tf[(f, k)] && t > Tmin[(f, k)]) <= D[(k, t)])
end

# (2) Arrival Capacity
for k in K, t in T
    @constraint(model,
        sum((w[f, k, t] - w[f, k, t - 1])
            for f in F if P[f][end] == k && t in Tf[(f, k)] && t > Tmin[(f, k)]) <= A[(k, t)])
end

# (3) Sector Capacity
for j in J, t in T
    @constraint(model,
        sum((w[f, j, t] - w[f, P[f][i + 1], t - 1])
            for f in F, i in 1:(N[f] - 1)
            if P[f][i] == j && t in Tf[(f, j)] && (t - 1) in Tf[(f, P[f][i + 1])]) <= S[(j, t)])
end

# (4) Min time in each sector
for f in F, i in 1:(N[f] - 1)
    j = P[f][i]
    j_next = P[f][i + 1]
    for t in Tf[(f, j)]
        t_exit = t + lfj[(f, j)]
        if t_exit in Tf[(f, j_next)]
            @constraint(model, w[f, j_next, t_exit] <= w[f, j, t])
        end
    end
end

# (5) Turnaround constraints
for (f1, f2) in C
    dep_airport = P[f2][1]
    arr_airport = P[f1][end]
    if dep_airport == arr_airport
        for t in Tf[(f1, arr_airport)]
            t2 = t + sf[f1]
            if t2 in Tf[(f2, dep_airport)]
                @constraint(model, w[f2, dep_airport, t2] <= w[f1, arr_airport, t])
            end
        end
    end
end

# (6) Monotonicity
for f in F, j in P[f], t in Tf[(f, j)], t > Tmin[(f, j)]
    @constraint(model, w[f, j, t] >= w[f, j, t - 1])
end

# (7) Force w = 0 before Tmin
for f in F, j in P[f]
    for t in Tmin[(f, j)-1:-1:1]
        fix(w[f, j, t], 0.0; force = true)
    end
end

# (8)
