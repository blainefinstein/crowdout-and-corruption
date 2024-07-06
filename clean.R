library(readxl)
library(purrr)
library(tidyverse)
library(TAF)
library(NLP)
library(stringr)
library(pdftools)

######################################################
#### Helper functions and variable initialization ####
######################################################

## Excel helper functions

# reads each sheet of the excel into a list
read_.xlsx <- function(path) {
  sheets <- excel_sheets(path)
  return(map(sheets, \(x) read_excel(path, sheet = x)))
}

# construct list of budget items to look up in data
f <- read_.xlsx("Budgets/2022/NCR/Caloocan-City-Annual-Audit-Report-2022/07-CaloocanCity2022_Part1-FS.xlsx")
a <- read_.xlsx("Budgets/2022/NCR/Caloocan-City-Annual-Audit-Report-2022/11-CaloocanCity2022_Part4-Annexes.xlsx")
items <- f[[1]] |> filter(!is.na(...2)) |> #Financial statement, first sheet 
  pull(...2) |> 
  append(f[[2]] |> filter(!is.na(...2)) |> pull(...2)) |> #second sheet
  append("Current Operating Expenses") |> 
  append(f[[3]][5:nrow(f[[3]]), ] |> pull('CITY OF CALOOCAN') |> na.omit()) |> #third sheet
  append(c("Transfer of PPE from Trust Fund/General Fund/OtherFund",
           "Prior Period Errors", "Prior Year's Adjustments")) |> 
  append(f[[4]][5:nrow(f[[4]]), ] |> pull(1) |> na.omit()) |>  #fourth sheet
  append(f[[4]] |> filter(!is.na(...2)) |> pull(...2)) |> 
  append(f[[4]] |> filter(!is.na(...3)) |> pull(...3)) |> 
  append(f[[5]][5:nrow(f[[5]]), ] |> pull(1) |> na.omit()) |>  #fifth sheet
  append(f[[5]] |> filter(!is.na(...2)) |> pull(...2)) |> 
  append(f[[5]] |> filter(!is.na(...3)) |> pull(...3)) |>
  append(a[[1]] |> filter(!is.na(...5)) |> pull(...5)) |> #Annex, first sheet
  append(c("Net Assets/Equity")) |> 
  append(a[[2]] |> filter(!is.na(...4)) |> pull(...4)) |> #second sheet
  append(a[[3]] |> filter(!is.na(...3)) |> pull(...3)) |> #third sheet
  append(a[[4]] |> filter(!is.na(...3)) |> pull(...3)) |> #fourth sheet
  append(a[[5]] |> filter(!is.na(...3)) |> pull(...3)) |> #fifth sheet
  append(a[[5]] |> filter(!is.na(...4)) |> pull(...4)) |>
  setdiff(c("A.", "B.", "C.")) |> 
  unique()

# construct list of col names for budget report df
cols <- c("lgu", "region", "year", "city") |> 
  append(f[[1]] |> filter(!is.na(...2)) |> pull(...2)) |> #Financial statement, first sheet
           append(f[[2]] |> filter(!is.na(...2)) |> pull(...2)) |> #second sheet
           append("Current Operating Expenses") |> 
           append(f[[3]][5:nrow(f[[3]]), ] |> pull('CITY OF CALOOCAN') |> na.omit()) |> #third sheet
           append(c("Transfer of PPE from Trust Fund/General Fund/OtherFund",
                    "Prior Period Errors", "Prior Year's Adjustments")) |> 
           append(f[[4]][5:nrow(f[[4]]), ] |> pull(1) |> na.omit()) |>  #fourth sheet
           append(f[[4]] |> filter(!is.na(...2)) |> pull(...2)) |> 
           append(f[[4]] |> filter(!is.na(...3)) |> pull(...3)) |> 
           append(f[[5]][5:nrow(f[[5]]), ] |> pull(1) |> na.omit()) |>  #fifth sheet
           append(f[[5]] |> filter(!is.na(...2)) |> pull(...2)) |> 
           append(f[[5]] |> filter(!is.na(...3)) |> pull(...3)) |>
  append(a[[1]] |> filter(!is.na(...5)) |> pull(...5) |> #Annex, first sheet
  append(c("Net Assets/Equity")) |> 
  append(a[[2]] |> filter(!is.na(...4)) |> pull(...4)) |> #second sheet
  append(a[[3]] |> filter(!is.na(...3)) |> pull(...3)) |> #third sheet
  append(a[[4]] |> filter(!is.na(...3)) |> pull(...3)) |> unique() |> 
    lapply(function(x) {
      list(paste0(x, " gen"), paste0(x, " sped"), paste0(x, " trust"))
    }) |> unlist()) |>
  append(a[[5]] |> filter(!is.na(...3)) |> pull(...3) |> #fifth sheet
  append(a[[5]] |> filter(!is.na(...4)) |> pull(...4)) |>
  setdiff(c("A.", "B.", "C.")) |> unique() |> 
    lapply(function(x) {
      list(paste0(x, " original"), paste0(x, " final"), paste0(x, " actual"))
    }) |> unlist()) |>
  sapply(function(x) {
    x <- tolower(x)                      # Convert to lower case
    x <- gsub(" ", "_", x)               # Replace spaces with underscores
    x <- gsub(",_", "_", x)              # Replace ",_" with "_"
    x <- gsub("/", "_", x)               # Replace "/" with "_"
    x <- gsub("_-_", "_", x)             # Replace "_-_" with "_"
    return(x)
  })

# fixes year to consistent whole number for key detection
round_year <- function(df, year) {
  # Convert to character
  df <- as.data.frame(lapply(df, as.character), stringsAsFactors = FALSE)
  
  # Construct regular expression pattern to find instances of the specified
  # number followed by decimals
  years <- paste0("\\b", year, "\\.\\d+\\b")
  
  # Loop through columns
  for (col in names(df)) {
    matches <- regmatches(df[[col]], gregexpr(years, df[[col]]))
    
    # Replace matched instances with the specified number
    for (i in seq_along(matches)) {
      for (match in matches[[i]]) {
        df[[col]][i] <- gsub(match, year, df[[col]][i])
      }
    }
  }
  
  # Convert back to numeric if columns were originally numeric
  for (col in names(df)) {
    if (is.numeric(df[[col]])) {
      df[[col]] <- as.numeric(df[[col]])
    }
  }
  
  return(df)
}

# see if col contains year, then rename col and round year appropriately
find_year <- function(data_frame, year) {
  for (col in names(data_frame)) {
    if (any(grepl(paste0("^", "2022", "$"), data_frame[[col]])) &&
        all(sapply(data_frame[[col]], is.numeric))) {
      names(data_frame)[names(data_frame) == col] <- "amount"
    }
  }
  return(round_year(data_frame, year))
}

# find annex funds and rename cols
funds <- c("General Fund", "Special Education", "Special Education Fund", "Trust Fund",
           "Original", "Final", "Actual Amounts")
find_funds <- function(df) {
  # Initialize list of new col names
  new <- c("gen", "sped", "sped", "trust", "original", "final", "actual")
  # Loop through each row in the data frame
  for (row in 1:nrow(df)) {
    # Loop through each col in the data frame
    for (col in 1:ncol(df)) {
      # Loop through fund names
      for (fund in funds) {
        # Check if cell matches fund name
        if(!is.na(df[row, col]) && df[row, col] == fund) {
          # Check if none of the values in the column contain any strings from the items list
          if (!any(df[(row+1):nrow(df), col] %in% items, na.rm = TRUE)) {
            # Rename the column to the corresponding fund name
            colnames(df)[col] <- new[which(funds == fund)]
          }
        }
      }
    }
  }
  return(df)
}

# return df of budget items in data + corresponding amounts
extract_.xlsx <- function(df) {
  # Initialize an empty data frame to store the results
  res <- data.frame(matrix(ncol = 0, nrow = 1))
  
  # Code to perform if df contains amount col
  if("amount" %in% names(df)) {
    # Loop through each string in the strings vector
    for (string in items) {
      # Create a regex pattern to match the string exactly
      pattern <- paste0("^", string, "$")
      
      # Loop through each column in the data frame
      for (col_name in names(df)) {
        # Check if the column contains the string exactly
        matching_rows <- which(grepl(pattern, df[[col_name]]))
        
        # If there's a match, add a new column to the result data frame
        if (length(matching_rows) > 0) {
          # Convert the string to lower case and replace spaces with underscores
          column_name <- tolower(gsub(" ", "_", string))
          
          # Extract the amount from the matching row
          amount <- df$amount[matching_rows[1]]
          
          # Add the amount as a new column to the result data frame
          res[[column_name]] <- amount
        }
      }
    }
  }
  
  # Code to perform if df contains gen, sped, and trust funds
  if("gen" %in% names(df)) {
    
    # Loop through each string in the strings vector
    for (string in items) {
      # Create a regex pattern to match the string exactly
      pattern <- paste0("^", string, "$")
      
      # Loop through each column in the data frame
      for (col_name in names(df)) {
        # Check if the column contains the string exactly
        matching_rows <- which(grepl(pattern, df[[col_name]]))
        
        # If there's a match, add a new column to the result data frame
        if (length(matching_rows) > 0) {
          # Convert the string to lower case and replace spaces with underscores
          column_name <- tolower(gsub(" ", "_", string))
          
          # Extract the amount from the matching rows
          gen <- df$gen[matching_rows[1]]
          sped <- df$sped[matching_rows[1]]
          trust <- df$trust[matching_rows[1]]
          
          # Add the amount as a new column to the result data frame
          res[[paste0(column_name, "_gen")]] <- gen
          res[[paste0(column_name, "_sped")]] <- sped
          res[[paste0(column_name, "_trust")]] <- trust
        }
      }
    }
  }
  
  # Code to perform if df contains original, final, and actual budgets
  if("original" %in% names(df)) {
    
    # Loop through each string in the strings vector
    for (string in items) {
      # Create a regex pattern to match the string exactly
      pattern <- paste0("^", string, "$")
      
      # Loop through each column in the data frame
      for (col_name in names(df)) {
        # Check if the column contains the string exactly
        matching_rows <- which(grepl(pattern, df[[col_name]]))
        
        # If there's a match, add a new column to the result data frame
        if (length(matching_rows) > 0) {
          # Convert the string to lower case and replace spaces with underscores
          column_name <- tolower(gsub(" ", "_", string))
          
          # Extract the amount from the matching rows
          original <- df$original[matching_rows[1]]
          final <- df$final[matching_rows[1]]
          actual <- df$actual[matching_rows[1]]
          
          # Add the amount as a new column to the result data frame
          res[[paste0(column_name, "_original")]] <- original
          res[[paste0(column_name, "_final")]] <- final
          res[[paste0(column_name, "_actual")]] <- actual
        }
      }
    }
  }
  
  # Column name repair
  colnames(res) <- gsub("_[:][_]", "_", colnames(res))
  colnames(res) <- gsub(",_", "_", colnames(res))
  colnames(res) <- gsub("/", "_", colnames(res))
  colnames(res) <- gsub("_-_", "_", colnames(res))
  
  # Return the result data frame
  return(res)
}

# Read in and clean one excel file
clean_excel <- function(path) {
  annex <- grepl("annex", path, ignore.case = TRUE)
  lgu <- gsub("-", " ", str_match(path, "/\\d{4}/[A-Za-z\\s]+/(.*)-Annual-Audit")[2])
  region <- str_match(path, "Budgets/\\d{4}/([A-Za-z\\s]+)/")[2]
  year <- str_match(path, "Budgets/(\\d{4})/")[2]
  city <- ifelse(grepl("city", path, ignore.case = TRUE), 1, 0)
  sheets <- read_.xlsx(path)
  res <- data.frame(
    lgu = lgu,
    region = region,
    year = year,
    city = city
  )
  
  # Loop over sheets and build observation out of budget report
  if(annex) {
    for (i in 1:length(sheets)) {
      res <- cbind(res, sheets[[i]] |> find_funds() |> extract.xlsx())
    }
  } else {
    for (i in 1:length(sheets)) {
      res <- cbind(res, sheets[[i]] |> find_year(2022) |> extract.xlsx())
    }
  }
  
  return(res)
}

## PDF helper functions

# read PDF
read_.pdf <- function(path) {
  # Read each page of PDf into list
  #pages <- pdf_text(path)
  pages <- tryCatch({
    pdf_text(path)
  }, error = function(err) {
    message("Error: ", conditionMessage(err))
    return("")
  })
  
  # Put all text from list into one string
  text <- ""
  for(i in 1:length(pages)) {
    text <- paste(text, pages[i])
  }
  
  # Clean text
  text <- gsub("\n", " ", text)
  text <- gsub("[()]", "", text)
  text <- gsub("\\s+", " ", text)
  text <- trimws(text)
  
  return(text)
}

# Find a line item in the budget text and return its corresponding amount
extract_number <- function(input_string, target_string) {
  # Regular expression to match the target string and the number pattern with optional parentheses
  pattern <- paste0(target_string, ".*?\\(?([0-9,]+\\.[0-9]{2})\\)?\\s")
  
  # Use str_extract to find the first match
  match <- str_extract(input_string, pattern)
  
  # Extract only the number from the match
  number <- str_match(match, "\\(?([0-9,]+\\.[0-9]{2})\\)?")[,2]
  
  # Return the result as a number without commas
  return(as.numeric(gsub(",", "", number)))
}

# Read in one PDF file and return budget report observation
clean_pdf <- function(path) {
  text <- read_.pdf(path)
  lgu <- gsub("-", " ", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)2022")[2])
  region <- str_match(path, "Budgets/\\d{4}/([A-Za-z\\s]+)/")[2]
  year <- str_match(path, "Budgets/(\\d{4})/")[2]
  city <- ifelse(grepl("city", path, ignore.case = TRUE), 1, 0)
  res <- data.frame(
    lgu = lgu,
    region = region,
    year = year,
    city = city
  )
  
  # Break code into fund types. Figure out how to do that
  
  # Loop over line items and build observation out of budget report
  for(string in items) {
    new <- data.frame(extract_number(text, string))
    names(new) <- tolower(string)
    res <- cbind(res, new)
  }
  
  # Column name repair
  colnames(res) <- gsub(" ", "_", colnames(res))
  colnames(res) <- gsub("_[:][_]", "_", colnames(res))
  colnames(res) <- gsub(",_", "_", colnames(res))
  colnames(res) <- gsub("/", "_", colnames(res))
  colnames(res) <- gsub("_-_", "_", colnames(res))
  
  return(res)
}

# Add one budget to df 
build <- function(df = NULL, obs) {
  # If null, build new df
  if(is.null(df)) {
    df <- data.frame(matrix(ncol = length(cols), nrow = 1))
    names(df) <- cols
    for (name in names(df)) {
      if(name %in% names(obs) && is.na(df[[name]])) {
        df[[name]] <- obs[[name]]
      }
    }
  } else {
    # If municipality name already in df, add to same row
    if(obs$lgu %in% df$lgu) {
      i <- which(df == obs$lgu)
      for (name in names(df)) {
        if(name %in% names(obs) && is.na(df[[name]][i])) {
          df[[name]][i] <- obs[[name]]
        }
      }
    } else {
      # If municipality name not already in df, add to new row
      new_row <- data.frame(matrix(ncol = length(cols), nrow = 1))
      names(new_row) <- cols
      for (name in names(df)) {
        if(name %in% names(obs) && is.na(new_row[[name]])) {
          new_row[[name]] <- obs[[name]]
        }
      }
      df <- rbind(df, new_row)
    } 
  }
  
  return(df)
}

# file name expressions that indicate a budget
audit_lang <- c("Part1-FS", "Part1-Financial_Statements", "Part4-Annexes")
pattern <- paste(audit_lang, collapse="|")

##################
#### Run code ####
##################

# Set directory from which to make budget data
directory <- "/Budgets/2022/Bangsamoro"

# Get unzipped directories (every other file)
places <- list.files(paste0(getwd(), directory)) |> 
  map(\(x) paste0(paste0(directory, "/"), x))
places <- places[seq_along(places) %% 2 != 0]

# Map over unzipped directories to get budget report file paths (if have zips)
paths <- places |> 
  map_df(function(x) {
    out <- list.files(x) |> 
      map_df(\(y) data.frame(path = paste0(paste0(x, "/"), y))) |> 
        filter(grepl(pattern, path == TRUE))
    return(budgets = out)
  }) |> rbind.data.frame()

# Turn list into data frame (no zips)
paths <- as.data.frame(as.matrix(places))

# Create data frame of budget reports
tictoc::tic()
budgets <- build(obs = clean_pdf(substring(paths[3,], 2)))
for (i in 4:nrow(paths)) {
  # If excel doc, run code to clean Excel docs
  if(grepl(".xlsx", paths[i,], ignore.case = TRUE)) {
    budgets <- build(budgets, obs = clean_excel(paths[i,]))
  }
  # If PDF, run code to clean PDFs
  if(grepl(".pdf", paths[i, ], ignore.case = TRUE)) {
    budgets <- build(budgets, obs = clean_pdf(substring(paths[i,], 2)))
  }
}
tictoc::toc()

