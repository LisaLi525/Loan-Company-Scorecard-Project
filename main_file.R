# Load necessary libraries
library(missForest)
library(rpart.plot)
library(ipred)
library(mboost)
library(randomForest)
library(kernlab)
library(e1071)
library(nnet)
library(neuralnet)
library(RSQLite)
library(DBI)
library(sqldf)

# Function to read and preprocess data
preprocess_data <- function(file_path) {
    data <- read.csv(file_path)
  
    # Replace NA values
    na_columns <- c('MAX_CPD', 'NOCALL_DAY', 'PTP_CONTACT', 'SALESCOMMISSION', 'CERTF_INTERVAL_YEARS', 'WK_3Y_EXP_NUM', 'CUS_CHILDRENTOTAL', 'FAMILY_INCOME')
    data[na_columns] <- lapply(data[na_columns], function(x) ifelse(is.na(x), -1, x))
    data$IS_INSURE[is.na(data$IS_INSURE)] <- "NA"
    data$IS_SSI[is.na(data$IS_SSI)] <- "NA"
  
    # Convert columns to factors
    factor_columns <- c('IS_INSURE', 'IS_SSI', 'CUS_SEX', 'CERT_4_INITAL')
    data[factor_columns] <- lapply(data[factor_columns], as.factor)
  
    # Select relevant columns
    data <- data[,c(3, 5:28)]
  
    return(data)
}

# Function to calculate WOE values
calculate_woe <- function(data, y, var) {
    total_counts <- table(data[[y]])
    woe_data <- data.frame(
        Var_Name = var,
        Group_Type = levels(data[[var]]),
        WOE = NA
    )
  
    for (level in levels(data[[var]])) {
        level_counts <- table(data[[y]], data[[var]] == level)
        p_0 <- level_counts[1] / total_counts[1]
        p_1 <- level_counts[2] / total_counts[2]
        woe_data$WOE[woe_data$Group_Type == level] <- log(p_1 / p_0)
    }

    # Replace Inf and -Inf with 3 and -3, respectively
    woe_data$WOE[is.infinite(woe_data$WOE)] <- ifelse(woe_data$WOE > 0, 3, -3)

    return(na.omit(woe_data))
}

# Load and preprocess data
data_path <- "C:/Users/hp/Desktop/R_DATA/bcard_28.csv"
data <- preprocess_data(data_path)

# Calculate WOE values for specified variables
woe_vars <- c("CUS_EDUCATION", "CUS_SEX", "IS_INSURE", "OTHER_PERSON_TYPE", "CUS_FAMILY_STATE", "WK_INDUSTRY", "IS_SSI", "WK_EXP_CUR", "CERT_4_INITAL")
woe_values <- do.call(rbind, lapply(woe_vars, function(var) calculate_woe(data, "TARGET", var)))

# Replace original variables with WOE values using SQL
sqldf_statement <- "
    SELECT 
        TARGET,
        MAX_CPD,
        NOCALL_DAY,
        PTP_CONTACT,
        FINISH_PERIODS_RATIO,
        SALESCOMMISSION,
        CUSTOMERSERVICERATES,
        CERTF_INTERVAL_YEARS,
        WK_3Y_EXP_NUM,
        CUS_CHILDRENTOTAL,
        LOWPRINCIPAL,
        ASSUME_CPD,
        EXTRA_INIT_RATE,
        PAY_CONSULT_MON,
        FAMILY_INCOME,
        (SELECT WOE FROM woe_values WHERE Var_Name = 'CUS_SEX' AND Group_Type = CUS_SEX) AS WOE_CUS_SEX,
        -- Repeat for other variables
    FROM data
"

data_with_woe <- sqldf(sqldf_statement)

# Perform imputation for missing values
imputed_data <- missForest(data_with_woe)$ximp
