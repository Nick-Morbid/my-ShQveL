import os
import sys
import argparse
import matplotlib.pyplot as plt
import pandas as pd
from collections import defaultdict


# parse the arguments
parser = argparse.ArgumentParser(description='Visualize the options of the DBMSs')
parser.add_argument('-d', '--directory', type=str, default="logs/", help='the directory of the logs')
args = parser.parse_args()

directory = args.directory
options = {}


# open all the file in one directory with the suffix "options.txt"
for filename in os.listdir(directory):
    if filename.endswith("Options.txt"):
        # open the file
        f = open(os.path.join(directory, filename), "r")
        lines = f.readlines()
        f.close()

        # extract the data
        # each line is OPTION : BOOL_VALUE
        data = defaultdict(bool)
        for line in lines:
            option, value = line.split(":")
            data[option.strip()] = value.strip() != "false"
        options.update({filename.removesuffix("Options.txt"): data})
        
# make the dict to pandas dataframe
df = pd.DataFrame.from_dict(options, orient='index').fillna(False)

# sort the columns by the number of True in the column
df = df.reindex(df.sum().sort_values(ascending=True).index, axis=1)
# sort the rows by the number of True in the row
df = df.reindex(df.sum(axis=1).sort_values(ascending=False).index)

print(df)
# plot a heat map of df

rows, cols = df.shape
plt.figure(figsize=(cols, rows))
plt.imshow(df, cmap='hot')
plt.xticks(range(len(df.columns)), df.columns, rotation=90)
plt.yticks(range(len(df.index)), df.index)
plt.xlabel("Options")
plt.ylabel("DBMSs")
plt.tight_layout()
plt.savefig("logs/options.png", dpi=60)