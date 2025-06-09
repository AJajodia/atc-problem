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
T = 1:15

P = Dict(f => flight_paths[!, f] for f in F) 

N = Dict(f => sum([P[f][step] != "0" for step in 1:nrow(flight_paths)]) for f in F) 

df = Dict(f => min_times_df[1, f] for f in F) 

rf = Dict(f => min_times_df[N[f], f] for f in F)

airports_list = string.(airports_df.airport)
sectors_list = string.(sectors_df.sector)
Sjt = Dict((j,t) => sectors_df[1, :sector_capacity] for j in sectors_list, t in T)
Sjt["1", 1]

