using JuMP
using GLPK

sectors_df = DataFrame(CSV.File("debug_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)
min_timetable_df = DataFrame(CSV.File("debug_flight_min_times.csv", header = false))
min_times_df = DataFrame(CSV.File("debug_min_times.csv", header = false))

all_sectors_list = vcat(string.(sectors_df.sector), string.(airports_df.airport))

flight_paths = DataFrame(CSV.File("debug_flight_paths.csv", header = false)) #all strings, 
                                                                            #rows = steps along path, cols = flights

# Initialize the model
model = Model(GLPK.Optimizer)

# INPUT DATA STRUCTURES

F = 1:ncol(min_timetable_df)            # Flights (just integer numbers)
K = string.(airports_df.airport)         # Airports

sectors_list = string.(sectors_df.sector)   # sectors without airports

J = all_sectors_list                    # all Sectors
T = 1:15                                # Time periods

P = Dict(f => flight_paths[!, f] for f in F)  
# P[f] = [sector_1, ..., sector_Nf] including airports,

N = Dict(f => sum([P[f][step] != "0" for step in 1:nrow(flight_paths)]) for f in F)   
# N[f] = length(P[f])

df = Dict(f => min_timetable_df[1, f] for f in F)         # df[f] = Scheduled departure time
rf = Dict(f => min_timetable_df[N[f], f] for f in F)      # Scheduled arrival time
#sf = Dict{Int, Int}()         # Turnaround time

cg = Dict(f => 10 for f in F)     # Ground delay cost, $10 for each flight
ca = Dict(f => 100 for f in F)     # Air delay cost, $100 for each flight


Dkt = Dict((k, t) => sectors_df[1, :depart_capacity] for k in K, t in T)

# Departure capacities D[k,t] at airport k = "A" at time t

Akt = Dict((k,t) => sectors_df[1, :arrival_capacity] for k in K, t in T)  
# Arrival capacities A[k,t] at airport k = "A" at time t

Sjt = Dict()
for j in J
    for t in T  
        if j in sectors_list
            Sjt[(j, t)] = sectors_df[1, :sector_capacity]
        elseif j in K
            Sjt[(j, t)] = sectors_df[1, :airport_capacity]
        end
    end
end
#sector capacities including airport capacaities, j = "1" or "A"

lfj = Dict()
for f in F
    for j in J
        if j in flight_paths[!, f]
            step = findfirst(==(j), flight_paths[!, f])
            lfj[(f, j)] = min_times_df[step, f]
        else
            lfj[(f, j)] = 0
        end
    end
end  
# Minimum time in sector j by flight f, given a sector "1" or "A",
#if j is in the path of f, find the step that j happens at (findfirst())
# and then return the minimum time f has to spend at that step

Tfj = Dict()
for f in F
    for j in P[f]
        step = findfirst(==(j), flight_paths[!, f])
        Tfj[(f, j)] = min_timetable_df[step, f]:(T[end]) 
    end
end  

# T^j_f: allowed arrival times at sector j for flight f, given a sector "1" or "A",
# that is in the path of f, find the step that j happens at (findfirst())
# and then return the minimum entry time and make exit to end of T (=15)

Tmin_fj = Dict()
for f in F
    for j in P[f]
        Tmin_fj[(f, j)] = Tfj[(f, j)][1]
    end
end 
# first allowed arrival

Tmax_fj = Dict()
for f in F
    for j in P[f]
        Tmax_fj[(f, j)] = Tfj[(f, j)][end]
    end
end 
# last allowed arrival (end of time period, 15)

#C = Vector{Tuple{Int, Int}}()  # Set of (f, f*) aircraft connections

# MAIN VARIABLES (w's)

@variable(model, w[f in F, j in P[f], t in Tfj[(f, j)]], Bin)

#  HELPER VARIABLES (u's)
# write u_ftj for simplicity
@expression(model, u[f in F, j in P[f], t in Tfj[(f, j)]], begin
    if t > Tmin_fj[(f, j)]
        w[f, j, t] - w[f, j, t - 1]
    else
        w[f, j, t]
    end
end)

# OBJECTIVE FUNCTION

# ground hold helper expression
@expression(model, g[f in F],
    sum(t * u[f, P[f][1], t] for t in Tfj[(f, P[f][1])]) - df[f])

# air hold helper expression
@expression(model, a[f in F],
    sum(t * u[f, P[f][end], t] for t in Tfj[(f, P[f][end])]) - rf[f] - g[f])

@objective(model, Min,
    sum(cg[f] * g[f] + ca[f] * a[f] for f in F))

# CONSTRAINTS

# Departure Capacity
for k in K, t in T
    @constraint(model,
        sum((w[f, k, t] - w[f, k, t - 1])
            for f in F if P[f][1] == k && t in Tfj[(f, k)] && t > Tmin_fj[(f, k)]) <= Dkt[(k, t)])
end

# Arrival Capacity
for k in K, t in T
    @constraint(model,
        sum((w[f, k, t] - w[f, k, t - 1])
            for f in F if P[f][end] == k && t in Tfj[(f, k)] && t > Tmin_fj[(f, k)]) <= Akt[(k, t)])
end

# Sector Capacity
for j in J, t in T
    @constraint(model,
        sum((w[f, j, t] - w[f, P[f][i + 1], t - 1])
            for f in F, i in 1:(N[f] - 1)
            if P[f][i] == j && t in Tfj[(f, j)] && (t - 1) in Tfj[(f, P[f][i + 1])]) <= Sjt[(j, t)])
end

# Min time in each sector
for f in F, i in 1:(N[f] - 1)
    j = P[f][i]
    j_next = P[f][i + 1]
    for t in Tfj[(f, j)]
        t_exit = t + lfj[(f, j)]
        if t_exit in Tfj[(f, j_next)]
            @constraint(model, w[f, j_next, t_exit] <= w[f, j, t])
        end
    end
end

# Turnaround constraints
#for (f1, f2) in C
#    dep_airport = P[f2][1]
#    arr_airport = P[f1][end]
#    if dep_airport == arr_airport
#        for t in Tf[(f1, arr_airport)]
#            t2 = t + sf[f1]
#            if t2 in Tf[(f2, dep_airport)]
#                @constraint(model, w[f2, dep_airport, t2] <= w[f1, arr_airport, t])
#            end
#        end
#    end
#end

# can't "un-arrive"
for f in F
    for j in P[f]
        for t in Tfj[(f, j)]
            if t > Tmin_fj[(f, j)]
                @constraint(model, w[f, j, t] >= w[f, j, t - 1])
            end
        end
    end
end

# Force w = 0 before Tmin
#for f in F, j in P[f]
#    t_max = Tmax_fj[(f, j)]
#    if haskey(w, (f, j, t_max))
#        fix(w[f, j, t_max], 1; force = true)
#    end
#end

# Force w = 1 at Tmax
#for f in F, j in P[f]
#    for t in ((Tmin_fj[(f, j)] - 1):-1:1)
#        if haskey(w, (f, j, t))
#            fix(w[f, j, t], 0; force = true)
#        end
#    end
#end

# SOLVE

optimize!(model)

# PRINT RESULTS

println("Objective value: ", objective_value(model))
for f in 1:4
    println("Flight ", f, ":")
    for j in P[f]
        for t in Tfj[(f, j)]
            println("w[$f, $j, $t] = ", value(w[f, j, t]))
        end
    end
end
