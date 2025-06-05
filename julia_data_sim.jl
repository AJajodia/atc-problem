using Random
using DataFrames
using CSV

airports <- CSV.read("mariah_airports.csv") 
timetable <- CSV.read("mariah_timetable.csv")