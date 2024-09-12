
######################################################
#### Helper functions and variable initialization ####
######################################################

# Load packages
source("packages.R")

# Read in list of budget items to look up in data
items <- readLines("items_2013.csv")
items <- gsub('^"|"$', '', items)

# List of budget items with redundant language
repeats <- c("Service and Business Income", "Non-Current Liabilities", "Expenditures",
             "Tax Revenue", "Non-Tax Revenue", "Revenue", "Property, Plant, and Equipment",
             "Non-Current Assets", "Business Income", "Payables", "Receipts from Printing and Publication",
             "Receipts from business/service income", "Current Liabilities")

# Construct list of col names for budget report df
cols <- c("lgu", "region", "year", "city") |> 
  append(items) |>
  sapply(function(x) {
    x <- tolower(x)                      # Convert to lower case
    x <- gsub(" ", "_", x)               # Replace spaces with underscores
    x <- gsub(",_", "_", x)              # Replace ",_" with "_"
    x <- gsub("/", "_", x)               # Replace "/" with "_"
    x <- gsub("_-_", "_", x)             # Replace "_-_" with "_"
    return(x)
  })

# Read in excel budget report and turn into text
read_.xlsx <- function(path) {
  # Get the names of all sheets
  sheet_names <- tryCatch(
    {
      read_sheets(path)
    },
    error = function(e) {
      # Return an empty string if an error occurs
      return("")
    })
  
  # End function if threw an error
  if (sheet_names == "") {
    return("")
  }

  
  # Initialize an empty string to store the final result
  final_str <- ""
  
  # Loop through each sheet and append its content to the final string
  for (sheet in sheet_names) {
    df <- read_excel(path, sheet = sheet)
    df_str <- capture.output(write.table(df, row.names = FALSE, sep = " ", quote = FALSE))
    df_str <- paste(df_str, collapse = "\n")
    final_str <- paste(final_str, paste("Sheet:", sheet), df_str, sep = " ")
  }
  
  # Print the final concatenated string
  return(final_str)
}

# Read in PDF budget report and turn into text
read_.pdf <- function(path) {
  # Read each page of PDf into list
  pages <- tryCatch({
    pdf_text(path)
  }, error = function(err) {
    message("Error: ", conditionMessage(err))
    return("")
  })
  
  # Combine all text from list into one string
  text <- ""
  for(i in 1:length(pages)) {
    text <- paste(text, pages[i])
  }
  
  # If that doesn't work, try OCR
  if(nchar(text) < 2500) {
    text <- sapply(1:pdf_info(path)$pages,
           \(x) ocr(image_read(pdf_render_page(path, page = x, dpi = 300)))) |> 
      paste(collapse = "\n")
  }
  
  # Clean text
  text <- gsub("\n", " ", text)
  text <- gsub("[()]", "", text)
  text <- gsub("\\s+", " ", text)
  text <- gsub("2022|2021|Special Education Fund|General Fund|Trust Fund", "", text)
  text <- trimws(text)
  
  return(text)
}

# Read in Word budget report and turn into text
read_.docx <- function(path) {
  # Read tables
  dat <- docx_extract_all_tbls(docxtractr::read_docx(path)) 
  
  # Initialize an empty string to store the final result
  final_str <- ""
  
  # Loop through each table and append its content to the final string
  for (i in 1:length(dat)) {
    df_str <- capture.output(write.table(dat[i], row.names = FALSE, sep = " ", quote = FALSE))
    final_str <- paste(final_str, paste(df_str, collapse = "\n"), sep = " ")
  }
  
  # If that doesn't work, convert to PDF and try OCR
  #if(grepl("^\\s*$", final_str)) {
    # Define temp output directory for PDF conversion
    output_dir <- "."
    
    # Full path to the LibreOffice executable
    libreoffice_path <- "/Applications/LibreOffice.app/Contents/MacOS/soffice"
    
    # Construct the system command
    cmd <- sprintf('%s --headless --convert-to pdf "%s" --outdir "%s"', libreoffice_path, path, output_dir)
    
    # Execute the command
    system(cmd, wait = TRUE)
    
    # Apply OCR
    temp_path <- gsub(".doc|.docx", ".pdf", gsub(".*/", "", path))
    final_str <- sapply(1:pdf_info(temp_path)$pages,
                   \(x) ocr(image_read(pdf_render_page(temp_path, page = x, dpi = 300)))) |> 
      paste(collapse = "\n")
    
    # Clean up and delete temp file
    file.remove(temp_path)
  #}
  
  # Print the final concatenated string
  return(final_str)
}

# Code to initialize region x year specific vars
initialize <- function(path) {
  lgu <<- gsub("-", " ", str_match(path, "/\\d{4}/[A-Za-z\\s]+/(.*)-Annual-Audit")[2])
  if(grepl(".xlsx|.xls", path)) {
    regular_exp <<- regular_exp <<- ".*?\\(?([0-9]{4,}(?:,[0-9]{3})*(?:\\.[0-9]+)?)\\)?(?=\\s)"
  }
  if(grepl(".pdf|.docx|.doc", path)) {
    regular_exp <<- regular_exp <<- "(?:(?![a-zA-Z]{3}).)*?\\(?([0-9,]+\\.[0-9]{2})\\)?\\s"
  }
  if(grepl("Bangsamoro", path) & grepl("2022", path)) {
    lgu <<- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)2022")[2])
    if(is.na(lgu)) {
      lgu <<- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)Audit_Report.pdf"))
    }
    lgu <<- gsub("([^A-Z])([A-Z])", "\\1 \\2", lgu)
  }
  if(grepl("Bicol", path) & grepl("2022", path)) {
    regular_exp <<- "(?:(?![=a-zA-Z]{3}).)*?\\(?([0-9,]+\\.[0-9]{2})\\)?[Pp\\|\\s]"
  }
  if(grepl("Calabarzon", path) & grepl("2022", path)) {
    lgu <<- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)2022")[2])
    if(is.na(lgu)) {
      lgu <<- gsub("[-_]", "", str_match(path, "/\\d{4}/[A-Za-z\\s]+/-?(.*)Audit_Report.pdf"))
    }
    lgu <<- gsub("([^A-Z])([A-Z])", "\\1 \\2", lgu)
  }
  if(grepl("2013|2014", path) & is.na(lgu)) {
    lgu <<- str_match(path, "/\\d{4}/[A-Za-z\\s]+/(.*)20")[2]
  }
}

# Find a line item in the budget text and return its corresponding amount
extract_number <- function(text, target_string, regular_exp) {
  # Regular expression to match the target string and the number pattern with optional parentheses
  pattern <- paste0(target_string, regular_exp)
  
  # Change regex to match budget items with repeat language
  pattern <- ifelse(target_string %in% repeats,
                    paste0("(?<!Total |Tax |of |Other |- )", pattern),
                    pattern)
  
  # Extract only the number from the match
  number <- str_match(text, pattern)[,2]
  
  # Return the result as a number without commas
  return(as.numeric(gsub(",", "", number)))
}

# Read in one budget report file and return observation
clean <- function(path) {
  initialize(path)
  text <- ifelse(grepl(".pdf", path, ignore.case = TRUE), read_.pdf(path),
                 ifelse(grepl(".xlsx|.xls", path, ignore.case = TRUE), read_.xlsx(path),
                        read_.docx(path)))
  region <- str_match(path, "Budgets/\\d{4}/([A-Za-z\\s]+)/")[2]
  year <- str_match(path, "Budgets/(\\d{4})/")[2]
  city <- ifelse(grepl("city", path, ignore.case = TRUE), 1, 0)
  res <- data.frame(
    lgu = lgu,
    region = region,
    year = year,
    city = city
  )
  
  # Loop over line items and build observation out of budget report
  for(string in items) {
    new <- data.frame(extract_number(text, string, regular_exp))
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

# Add one budget to df of budget reports
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
    if(obs$lgu %in% df$lgu && is.na(obs$lgu) == FALSE) {
      i <- which(df == obs$lgu)
      for (name in names(df)) {
        if(is.null(df[[name]][i]) == FALSE && is.na(df[[name]][i]) == TRUE) {
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

# File name expressions that indicate a budget
audit_lang <- c("Part1-FS", "Financial_Statements", "Audit_Report.pdf", "FS.pdf",
                "Audit_Report.docx", "Part1-Audited_FS", "FS.xlsx", "Audit_Report.doc",
                "FS.doc", "Notes_to_FS", "Observations_and_Recommendations") |> 
  paste(collapse = "|")

# Take directory and optional df of existing data and return data frame of budget reports
make_data <- function(dir, df = NULL) {
  # Get file paths of budgets in directory
  paths <- list.files(paste0(getwd(), dir), recursive = TRUE) |> 
    map(\(x) paste0(paste0(dir, "/"), x)) |> 
    as.matrix() |> 
    as.data.frame()
  names(paths) <- "path"
  paths <- paths |> filter(grepl(audit_lang, path) == TRUE & !grepl("\\$", path))
  
  # Create data frame of budget reports
  res <- df
  for (i in 1:nrow(paths)) {
    if(!grepl("zip", paths[i,])) {
      # Return null if observation throws an error
      tryCatch({
        res <- build(res, obs = clean(substring(paths[i,], 2)))
        print(paths[i,])},
        error = function(e) {
          print("ERROR!!!! ERROR!!!! Didn't process: ")
          print(paths[i,])
        })
    }
  }
  
  return(res)
}

##################
#### Run code ####
##################

# Set directory from which to make budget data
directory <- "/Budgets/2013/Eastern Visayas"

# Create data frame of budget reports
tictoc::tic()
eastvisayas_2013 <- make_data(directory)
tictoc::toc()
