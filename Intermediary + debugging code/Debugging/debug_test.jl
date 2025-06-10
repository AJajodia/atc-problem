using JuMP
using GLPK

sectors_df = DataFrame(CSV.File("debug_airport_sectors.csv"))
airports_df = filter(row -> all(x -> x != "NA", row), sectors_df)
min_timetable_df = DataFrame(CSV.File("debug_flight_min_times.csv", header = false))

all_sectors_list = vcat(string.(sectors_df.sector), string.(airports_df.airport))

flight_paths = DataFrame(CSV.File("debug_flight_paths.csv", header = false)) #all strings, 
                                                                            #rows = steps along path, cols = flights

# Initialize the model
model = Model(GLPK.Optimizer)

# === INPUT DATA STRUCTURES (to be filled with real data) ===

F = 1:ncol(min_timetable_df)            # Flights (just integer numbers)
K = string.(airports_df.airport)         # Airports

sectors_list = string.(sectors_df.sector)   # sectors without airports

J = all_sectors_list                    # all Sectors
T = 1:15    

P = Dict(f => flight_paths[!, f] for f in F) 

N = Dict(f => sum([P[f][step] != "0" for step in 1:nrow(flight_paths)]) for f in F) 

df = Dict(f => min_timetable_df[1, f] for f in F) 

rf = Dict(f => min_timetable_df[N[f], f] for f in F)

airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)

Sjt = Dict()
for j in vcat(sectors_list, airports_list)
    for t in T  
        if j in sectors_list
            Sjt[(j, t)] = sectors_df[1, :sector_capacity]
        elseif j in airports_list
            Sjt[(j, t)] = sectors_df[1, :airport_capacity]
        end
    end
end

min_times_df = DataFrame(CSV.File("debug_min_times.csv", header = false))

lfj = Dict()
for f in F
    for j in vcat(sectors_list, airports_list)
        if j in flight_paths[!, f]
            step = findfirst(==(j), flight_paths[!, f])
            lfj[(f, j)] = min_times_df[step, f]
        else
            lfj[(f, j)] = 0
        end
    end
end

Tfj = Dict()
for f in F
    for j in P[f]
        step = findfirst(==(j), flight_paths[!, f])
        Tfj[(f, j)] = min_timetable_df[step, f]:(T[end]) 
    end
end 

Tmin_fj = Dict()
for f in F
    for j in P[f]
        Tmin_fj[(f, j)] = Tfj[(f, j)][1]
    end
end 

Tmax_fj = Dict()
for f in F
    for j in P[f]
        Tmax_fj[(f, j)] = Tfj[(f, j)][end]
    end
end 


P[3]

