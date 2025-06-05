using Random
using DataFrames
using CSV

airport_sectors = CSV.read("mariah_airport_sectors.csv", DataFrame) 
timetable = CSV.read("mariah_timetable.csv", DataFrame)

airport_dict = Dict(row.airport => (row.lat, row.long) for row in eachrow(airport_sectors))