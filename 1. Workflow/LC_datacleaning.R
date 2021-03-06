directory = "C:/Projects/lendingclub"
setwd(directory)
lc <- read.csv("LoanStats3b.csv", stringsAsFactors = FALSE)

library(dplyr)
library(ggplot2)
library(tidyr)
library(tidyverse)
library(dummies)
library(lubridate)
library(xgboost)

# Data Table & Feature Manipulation ---------------------------------------------
# Find dimensions of both tables
dim(lc)

lc2 <- lc[c('loan_status','loan_amnt', 'term','int_rate','emp_length',
            'home_ownership','annual_inc','verification_status','issue_d',
            'purpose','dti','delinq_2yrs','inq_last_6mths',
            'mths_since_last_delinq','mths_since_last_record','open_acc',
            'pub_rec', 'total_acc','collections_12_mths_ex_med',
            'mths_since_last_major_derog','acc_now_delinq','chargeoff_within_12_mths', 
            'mo_sin_old_il_acct','mths_since_recent_bc_dlq','mths_since_recent_inq',
            'mths_since_recent_revol_delinq','num_accts_ever_120_pd','num_actv_bc_tl',
            'num_actv_rev_tl','pub_rec_bankruptcies','tax_liens')]

# Converting characters to integers
lc2$term <- substr(lc2$term,1,3)
lc2$term <- as.integer(lc2$term)

lc2$int_rate <- as.numeric(gsub("%","",lc2$int_rate))/100

# Fixing Dates to Months Since August 2007 (FOUNDING MONTH)
lc2$issue_dsincelc<-mdy(paste(substr(lc2$issue_d, 1,3),"01",substr(lc2$issue_d,5,6)))
lc2$issue_dsincelc<-round(difftime( lc2$issue_dsincelc , ymd("2007-08-01"), units= 'day')/365.25,3)
lc2$issue_dsincelc <- as.numeric(lc2$issue_dsincelc)

lc2$issue_d <- NULL

# Defining Loan Default (1 - Defaulted, 0 - Not Defaulted)
lc2$loan_status2 <- recode(lc2$loan_status, "Charged Off" = 1, "Default" = 1, "Current" = 0,
                           "Fully Paid" = 0, "In Grace Period" = 0, "Late (16-30 days)" = 0,
                           "Late (31-120 days)" = 0)
lc2$loan_status2 <- as.factor(lc2$loan_status2)
lc2$loan_status <-NULL
  
# Execute Data Exploration Before Creating Dummy Variables 

# Categorizing (or Recategorizing) Data & Creating Dummmy Variables
lc2$emp_length <- recode(lc2$emp_length, "< 1 year"="0-2", "1 year" = "0-2",
                         "2 years" = "0-2", "3 years" = "3-5","4 years" = "3-5", 
                         "5 years" = "3-5", "6 years" = "6-10", "7 years" = "6-10",
                         "8 years" = "6-10","9 years" = "6-10","10 years" = "6-10",
                         "10+ years" = "10+")

lc2$mths_since_last_delinq <- cut(lc2$mths_since_last_delinq, breaks= c(0,12,24,60,Inf), labels=c("0-12","13-24","25-60","60+"))
lc2$mths_since_last_record <- cut(lc2$mths_since_last_record, breaks= c(0,12,24,48,84,Inf), labels=c("0-12","13-24","25-48","49-84","85+"))
lc2$mths_since_last_major_derog <- cut(lc2$mths_since_last_major_derog, breaks= c(0,12,24,48,84,Inf), labels=c("0-12","13-24","25-48","49-84","85+"))
lc2$mths_since_recent_bc_dlq <- cut(lc2$mths_since_recent_bc_dlq, breaks= c(0,12,24,48,84,Inf), labels=c("0-12","13-24","25-48","49-84","85+"))
lc2$mo_sin_old_il_acct <- cut(lc2$mo_sin_old_il_acct, breaks= c(0,12,24,48,96,144,192,Inf), labels=c("0-12","13-24","25-48","49-96","97-144","145-192","193+"))
lc2$mths_since_recent_inq <- cut(lc2$mths_since_recent_inq, breaks= c(0,1,3,12,24,Inf), labels=c("0-1","2-3","4-12","13-24","25+"))
lc2$mths_since_recent_revol_delinq<- cut(lc2$mths_since_recent_revol_delinq, breaks= c(0,12,24,48,84,Inf), labels=c("0-12","13-24","25-48","49-84","85+"))

lc2 <- lc2 %>% filter(lc2$home_ownership != "ANY")

lc2$verification_status <- recode(lc2$verification_status, "Not Verified" = "NotVerified", "Source Verified" = "SourceVerified")

lc2<- dummy.data.frame(lc2, names = c('emp_length','home_ownership', 'verification_status', 'purpose','mths_since_last_delinq',
                                      'mths_since_last_record','mths_since_last_major_derog', 'mths_since_recent_bc_dlq',
                                      'mo_sin_old_il_acct','mths_since_recent_inq', 'mths_since_recent_revol_delinq'),sep = "_")
lc2$"emp_length_n/a" <- NULL
lc2$home_ownership_RENT <- NULL
lc2$verification_status_NotVerified<- NULL
lc2$purpose_other <- NULL
lc2$mths_since_last_record_NA <- NULL
lc2$mths_since_last_delinq_NA <- NULL
lc2$mths_since_last_major_derog_NA <- NULL
lc2$mths_since_recent_bc_dlq_NA <- NULL
lc2$mo_sin_old_il_acct_NA <- NULL
lc2$mths_since_recent_inq_NA <- NULL
lc2$mths_since_recent_revol_delinq_NA <- NULL

# Impute Values
lc2[c('num_accts_ever_120_pd')][is.na(lc2[c('num_accts_ever_120_pd')])] <- 0

lc2$num_actv_bc_tl[is.na(lc2$num_actv_bc_tl)] =median(lc2$num_actv_bc_tl, na.rm=TRUE)
lc2$num_actv_rev_tl[is.na(lc2$num_actv_rev_tl )] =median(lc2$num_actv_rev_tl , na.rm=TRUE)

# Final Export for Python TPOT------------------------------------------------------------------
# write.csv(lc2, file = "lcclean.csv", row.names = FALSE)
