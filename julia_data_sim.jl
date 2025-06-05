using Random
using DataFrames
using CSV

airport_sectors <- CSV.read("mariah_airport_sectors.csv") 
timetable <- CSV.read("mariah_timetable.csv")