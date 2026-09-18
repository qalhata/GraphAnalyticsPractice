---
title: "Graph Data Science with Neo4j"
subtitle: "A hands-on lab: finding hidden structure in a criminal network"
---

# What this lab is

Yesterday you computed centrality measures on a network using Python and networkx. Today you will do the same thing, and a good deal more, against a real graph database.

By the end of ninety minutes you will have:

- Built a graph database from eight CSV files, using the pattern a production pipeline would use
- Written queries that answer questions which are genuinely difficult in SQL, with the SQL alongside so you can judge that claim for yourself
- Detected a money laundering pattern that no row-level rule could find
- Run six graph algorithms and found the most important person in the network, who turns out not to be who you would expect
- Tested what happens to the network if that person is removed
- Argued about whether one of the queries should exist at all

**You do not need to have used Neo4j before.** Everything you need is in this document. If you are already comfortable with graphs, the "Go further" boxes will keep you occupied.

**A note on the dataset.** It is a synthetic criminal network: fifteen people, twelve bank accounts, phone records, transfers and an organisational hierarchy. It is not from your domain, and you will notice that.

The key learning here is building a mental model of well constructed patterns in network analysis, and recognising that the algorithms do not care about the domain. Betweenness centrality on a criminal network and betweenness centrality on a data lineage graph are the same computation. **Your subject matter expertise is what determines your abstraction from the concepts**, which is why the translation back to your own work sits at the end of this guide rather than being done for you.

The final section of the lab asks you to think hard about where that abstraction should stop.

---

# Part 0: Setup

## What you need

- **Neo4j Desktop**, already installed on your VM
- The eight CSV files, either downloaded or loaded from a URL (both routes below)
- **`lab-queries.cypher`**, which is the plain text file you will copy queries from

> **Copy your Cypher from `lab-queries.cypher`.** Open it in the repository and use the
> **Raw** view or the copy button, or open the downloaded file in a text editor. This
> guide tells you which block to run; the file is where the code lives.
>
> **If you are reading a PDF or Word copy of this guide, do not copy code out of it.**
> Those formats convert straight quotes into curly quotes, which Neo4j rejects with a
> syntax error. Reading from them is fine. Copying from them is not.

## Step 1: Create the instance

1. Open Neo4j Desktop and click **Create Instance**.
2. Name it `legAnalytics`, choose the Neo4j version your instructor specifies, and set a password you will remember. `training123` is fine for a lab. **Everyone should use the same version**, because the Graph Data Science library is matched to one Neo4j release at a time and a mismatch means a procedure works on one machine and not another.
3. Start the instance with the **play** button.
4. **Install the plugin now, before you do anything else.** Click the **three dots** next to the instance name, open the plugins panel, find **Graph Data Science Library**, install it, and **restart the instance**. If you skip this, everything up to Part 4 works and then nothing does.
5. Click **Create database**, name it `CrimeNetDB`, then **Connect**.
6. At the top of the query window, switch the database from `neo4j` to `crimenetdb`.

### Users and databases: why you stay as `neo4j`

**The `neo4j` user belongs to the instance, not to a database.** Creating `CrimeNetDB` does not create a new user and does not need one: `neo4j` is the administrator for the whole instance and can query every database inside it.

The confusion to avoid is that **there is also a database called `neo4j`**, created by default alongside yours. Same name, unrelated thing. Switching the selector at the top of the query window changes which **database** your queries run against. Your **user** does not change, and does not need to.

Two practical notes:

- **Neo4j stores database names in lower case**, so `CrimeNetDB` becomes `crimenetdb`. That is expected, not a mistake.
- **Confirm the selector reads `crimenetdb` before you load anything.** If it still says `neo4j`, everything loads into the default database instead, and later queries return nothing for no apparent reason. The editor prompt shows it too, as `crimenetdb$`.

## Step 2: Confirm the plugin

Run this. If it returns a version number you are ready.

```cypher
RETURN gds.version() AS GDSVersion;
```

If it fails with "unknown function", the plugin is not installed or the instance was not restarted after installing it. Go back to step 4.

## Step 3: Get the files, and choose how you will load the data

The repository holds the eight CSV files, `lab-queries.cypher`, and this guide.

> **Download everything now, at the start of the session, not afterwards.**
> The repository is public for the duration of this course and goes private after it.
> Once it does, the raw URLs stop resolving, so anyone who wants to repeat the lab
> later needs a local copy. Two minutes now saves an unexplainable failure in a month.

There are two routes for getting the data into Neo4j. **Pick one and stay with it.** Everything after this point is identical either way.

### Route A: load straight from the repository (the default)

**Nothing to edit. The URLs in `lab-queries.cypher` are live and ready to run.** Copy and paste each block as it stands.

The base URL they use is:

```
https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/
```

To confirm it works on this VM before you start, paste this into a browser:

```
https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/persons.csv
```

If you see the CSV text, Route A will work. If you get an error or a blocked page, use Route B.

**Route A depends on the repository being public.** It is public for the duration of this course. If you come back to this lab afterwards and the loads fail, that is why, and Route B is your answer, which is the reason to download the files now.

### Route B: load from local files

1. Download the eight CSV files from the repository.
2. In Neo4j Desktop, with the instance selected, click the **three dots**, choose **Open**, then **Instance Folder**, then the **import** subfolder. A file browser opens.
3. Copy all eight CSVs into that folder.
4. In `lab-queries.cypher`, do one find-and-replace:

- **Find:** `https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/`
- **Replace with:** `file:///`

So `'https://raw.../persons.csv'` becomes `'file:///persons.csv'`.

**Route B is the more reliable one** if you are on a managed machine, it keeps working when the repository goes private, and it is closer to how a locked-down production environment behaves: the data comes to the database rather than the database reaching out to the internet.

## Step 4: How to run the queries

Paste one block at a time and press the play button or **Ctrl+Enter**. Blocks are separated by blank lines in `lab-queries.cypher` and each ends with a semicolon.

> **Tip worth adopting now.** Neo4j's query editor lets you save queries into folders. Make four: **Load**, **Verify**, **Cypher**, **Analytics**. You will want them again, and it is the habit that turns a lab into something reusable.

---

# Part 1: Load the data (20 minutes)

## 1.1 to 1.4: Reset and constraints

Run blocks **0.1** through **0.4**.

**What you are doing.** Clearing anything already in the database, then creating two uniqueness constraints and two indexes **before** loading any data.

**Why this order matters.** A uniqueness constraint creates its own index and it makes an accidental second load **fail loudly** instead of silently doubling your graph. If you create indexes at the end, a double-run has already corrupted the data by the time you notice. This is a production habit worth carrying into any database work.

> **What you should see.** Two constraints listed by `SHOW CONSTRAINTS`.

## 1.5: Load the people and the accounts

Run blocks **1.1** and **1.2**.

**What you are doing.** Reading each CSV row by row and creating a node for each one.

Three things in that code are worth understanding rather than just running.

- **`MERGE` on the key, then `SET` the rest.** `MERGE (p:Person {id: trim(row.id)})` finds the person if they exist and creates them if not. Then `SET` fills in the properties. `CREATE` would also work, once. `MERGE` works every time, which is what you need in a pipeline that reruns nightly. This is called an idempotent load.
- **`trim()` on every text field.** The two node files were saved with Windows line endings and the six relationship files were not. Different tool, different day, same folder. Without trimming, a status of `ACTIVE` can arrive as `ACTIVE` plus an invisible carriage return, which then fails every filter you write and produces **no error at all**. Defensive trimming costs nothing.
- **The `CASE` around `dateOfBirth`.** Three people have no date recorded. `date(null)` throws an error and rolls back the whole load, so the `CASE` returns `null` instead.

> **What you should see** from block 1.3: **Account 12, Person 15**.

## 1.6: The checkpoint that matters most

Run block **1.4**.

**What you are doing.** Checking that the values loaded correctly, not just that the rows loaded.

> **What you should see.** Six status values and **no null row**:
>
> | Status | People |
> |---|---|
> | CLEAN | 5 |
> | ASSOCIATE | 4 |
> | BENEFICIARY | 2 |
> | KNOWN_OFFENDER | 2 |
> | MONEY_MULE | 1 |
> | PERSON_OF_INTEREST | 1 |

**If you see a null row, stop and fix it before going on.** An earlier version of this lab had a two-character typo in the load that set every status to `null`. Row counts were perfect. Half the queries later in the lab then returned nothing, and it looked like a data problem. It was not.

**The habit to take away.** After any load, verify the values, not only the count. "Fifteen rows loaded" and "fifteen rows loaded correctly" are different claims, and only one of them is useful.

## 1.7: Who is missing data?

Run block **1.5**.

> **What you should see.** Three people with no date of birth, and a null in the Address column: **Elena Popov, Robert Clark and Nina Davis.**

**Look at their roles.** One associate and two street-level people. The records with the least information are the ones furthest from the centre of the network. **The missingness is telling you something about position.** An absent value is often a fact rather than a gap, and deciding which it is comes before deciding how to handle it.

## 1.8: The addresses, which are a warning about synthetic data

Run block **1.6**, which lists the people whose records are complete, and read the Address column.

> **What you should see.** Shady Lane. Dark Street. Suspect Avenue. Loyal Street. Trust Road. Innocent Lane. Clean Avenue. Mule Street. Clean Money Road. Laundered Boulevard.

**Whoever generated this data wrote the answer into the address field.** A model trained on it could reach high accuracy by reading the street name and nothing else, and it would look like a triumph.

Synthetic data always encodes the assumptions of whoever generated it. Usually those assumptions are subtle and you have to go looking for them. Here they are written in capital letters, which makes this a useful thing to have seen before the first time someone offers you a generated dataset to train on.

## 1.9: Load the relationships

Run blocks **2.1** through **2.6**, one at a time.

**Every relationship in Neo4j has a direction**, whether or not the direction carries any meaning. You choose one when you load and then ignore it when you query if it does not matter.

- **`COMMANDS`: the direction is the meaning.** Boss to lieutenant. Reverse it and the org chart inverts.
- **`KNOWS`: the direction is an artefact.** We store it with an arrow and query it without one.
- **`CALLED` and `TRANSFERRED_TO`: `MERGE` is keyed on the timestamp.** There are eleven separate calls between one pair of people. If the merge key were just the pair, eleven calls would collapse into one and the frequency signal would be gone, which is the very thing you are about to analyse. **That is a modelling decision, not a syntax detail.**
- **`CONTROLS` against `OWNED_BY`.** Controls means the person can transact on the account. Owned by means they are the legal owner, who may have no access and may not even know. Hold on to that distinction, because the most interesting query in this lab depends on it.

> **What you should see** from block 2.7: CALLED 26, TRANSFERRED_TO 12, COMMANDS 10, KNOWS 10, CONTROLS 3, OWNED_BY 2. **Total 63.**

---

# Part 2: Asking questions with Cypher (25 minutes)

## 2.1: Look at it first

Run block **3.1**, then click the **Graph** tab.

**Before any algorithm, look at the thing.** Same principle as plotting your data before you model it. Note that there appear to be two clusters of people, and a chain of accounts sitting somewhat apart.

## 2.2: Who controls money?

Run block **3.2**.

> **What you should see.** Three people: **John Doe** (KNOWN_OFFENDER), **Carlos Mendez** (KNOWN_OFFENDER), **James Chen** (MONEY_MULE).

Three controllers and twelve accounts, so nine accounts have no controller recorded. In an investigation that gap is the next question, not a complaint about data quality.

## 2.3: Two degrees of separation

Run block **3.3**.

**Read the pattern as a sentence.** Start at John Doe, follow one or two `KNOWS` or `CALLED` relationships in either direction, and return the people you land on.

```
(suspect:Person {name: 'John Doe'})-[:KNOWS|CALLED*1..2]-(associate:Person)
```

- The `|` means either relationship type.
- **`*1..2` is the variable-length hop**, and it is the single most important piece of Cypher syntax in this lab.
- No arrowhead means direction does not matter here.
- `min(length(path))` because several routes reach the same person and you want the shortest.

### The same question in SQL

This is the comparison worth pausing on, and you have just written the Cypher so you know exactly what it does. **You do not need to read the SQL line by line. Look at the shape of it.**

```sql
WITH RECURSIVE associates AS (
    -- Direct associates, forward direction
    SELECT p2.person_id, p2.name, p2.phone, 1 AS degree,
           CAST(p1.name || ' -> ' || p2.name AS VARCHAR(4000)) AS path
    FROM persons p1
    JOIN relationships r1 ON p1.person_id = r1.person1_id
    JOIN persons p2      ON r1.person2_id = p2.person_id
    WHERE p1.name = 'John Doe'

    UNION

    -- Direct associates, reverse direction
    SELECT p2.person_id, p2.name, p2.phone, 1 AS degree,
           CAST(p1.name || ' -> ' || p2.name AS VARCHAR(4000)) AS path
    FROM persons p1
    JOIN relationships r1 ON p1.person_id = r1.person2_id
    JOIN persons p2      ON r1.person1_id = p2.person_id
    WHERE p1.name = 'John Doe'

    UNION ALL

    -- Second degree, forward direction
    SELECT p3.person_id, p3.name, p3.phone, a.degree + 1,
           CAST(a.path || ' -> ' || p3.name AS VARCHAR(4000))
    FROM associates a
    JOIN relationships r2 ON a.person_id = r2.person1_id
    JOIN persons p3      ON r2.person2_id = p3.person_id
    WHERE a.degree < 2
      AND p3.name <> 'John Doe'

    UNION

    -- Second degree, reverse direction
    SELECT p3.person_id, p3.name, p3.phone, a.degree + 1,
           CAST(a.path || ' -> ' || p3.name AS VARCHAR(4000))
    FROM associates a
    JOIN relationships r2 ON a.person_id = r2.person2_id
    JOIN persons p3      ON r2.person1_id = p3.person_id
    WHERE a.degree < 2
      AND p3.name <> 'John Doe'
)
SELECT DISTINCT name, phone, degree, path
FROM associates
ORDER BY degree, name;
```

**Thirty-nine lines against nine, and the line count is the least interesting part of it.** Four things are happening in that SQL that the Cypher did not have to do:

- **Four branches, because direction has to be handled manually.** Cypher's `-` with no arrowhead traverses both ways in one expression. SQL needs a separate branch for forward and reverse, at each level.
- **The depth is hard-coded into the query's structure.** `WHERE a.degree < 2` plus one branch per level. Changing `*1..2` to `*1..3` in Cypher is one character. In SQL it is a structural rewrite.
- **The path has to be reconstructed by hand**, as a concatenated string that you then parse back out. Cypher hands you the path as an object you can slice, count and return.
- **It assumes one relationships table.** This query only handles a single relationship type. **Our Cypher covered `KNOWS` and `CALLED` together, with one `|` character.** Doing that in SQL means either a union per type, or a table with nullable columns for every relationship type's metadata: `amount` for transfers, `duration` for calls, `since` for social ties. Add a third type and it roughly doubles again.

**And the performance story runs the same way.** A relational optimiser handles two hops adequately and degrades sharply beyond three, because each level is another self-join over the whole table. A graph database stores the relationships as pointers on the node itself, so traversing one hop costs the same whether the database holds a thousand nodes or a billion. That property is called index-free adjacency and it is the actual reason graph databases exist.

> **The reasonable counterweight, because this is not a one-sided argument.** SQL is better at aggregation over large flat tables, at transactional guarantees, and at everything your existing estate already does well. **A graph database is a specialist tool for connected data, not a replacement for your warehouse.** The question to ask is not which is better, but where in your own work the connections carry the signal. That is the only place this belongs.

> **Go further.** Change `*1..2` to `*1..3` and rerun. How many people does John Doe reach in three hops? Then try `*1..4`. At what point does the answer stop being useful?

## 2.4: The organisational hierarchy

Run block **3.4**.

Note the arrow this time: `-[:COMMANDS*1..4]->`. **Here direction is the hierarchy**, so you must keep it.

The slice `nodes(path)[1..-1]` drops the first and last node in the path and returns everyone in between, which gives you the chain of command.

> **What you should see.** A four-level org chart under Carlos Mendez, with each member's reporting level and the chain above them.

### The same question in SQL

A recursive hierarchy is the one case where SQL has a reasonable answer, so this is the fairer comparison of the two.

```sql
WITH RECURSIVE org_hierarchy AS (
    -- Base case: direct reports
    SELECT p1.person_id AS boss_id,
           p2.person_id AS subordinate_id,
           p2.name      AS subordinate_name,
           p2.role,
           1 AS level,
           CAST(p2.name AS VARCHAR(4000)) AS chain
    FROM persons p1
    JOIN command_relationships cr ON p1.person_id = cr.commander_id
    JOIN persons p2               ON cr.subordinate_id = p2.person_id
    WHERE p1.name = 'Carlos Mendez'

    UNION ALL

    -- Recursive case: indirect reports
    SELECT oh.boss_id, p3.person_id, p3.name, p3.role, oh.level + 1,
           CAST(oh.chain || ' -> ' || p3.name AS VARCHAR(4000))
    FROM org_hierarchy oh
    JOIN command_relationships cr ON oh.subordinate_id = cr.commander_id
    JOIN persons p3               ON cr.subordinate_id = p3.person_id
    WHERE oh.level < 4
)
SELECT subordinate_name AS Member,
       role             AS Role,
       level            AS ReportingLevel,
       chain            AS ChainOfCommand,
       CASE level
           WHEN 1 THEN 'Direct Lieutenant'
           WHEN 2 THEN 'Cell Leader'
           WHEN 3 THEN 'Operative'
           ELSE 'Street Level'
       END AS HierarchyLevel
FROM org_hierarchy
ORDER BY level, subordinate_name;
```

**Thirty-five lines against seventeen, and this time the SQL is genuinely readable.** Direction is fixed, so there is only one branch. There is one relationship type, so there is one join path. **This is what SQL looks like when the problem suits it**, and it is worth seeing so that the previous comparison does not read as a stitch-up.

Two differences remain, and they are the ones that decide it in practice:

- **The chain of command is still a concatenated string** that you have to parse if you want to do anything with it. Cypher's `nodes(path)[1..-1]` gives you a list.
- **Add a second relationship type and the two diverge again.** Ask "who commands or influences whom" and the Cypher gains `|:INFLUENCES`. The SQL gains another join path inside both branches of the recursion.

> **Go further.** Reverse the arrow to `<-[:COMMANDS*1..4]-` and rerun. You now get everyone **above** a person instead of below them. One character, opposite question.

## 2.5: Communication patterns

Run block **3.5**.

> **What you should see.** Exactly two rows, both at **11 calls**: John Doe to Sarah Kim, and Tommy Barnes to Lisa Johnson.

Twenty-six calls in the whole log and twenty-two of them are these two pairs. **That concentration is the finding.** Remember the name Sarah Kim, because she comes back.

## 2.6: The showpiece: detecting money laundering

Run block **3.6**. Read it before you run it.

**Read the pattern top to bottom and it is a sentence:** a known offender controls an account, money moves out of it through up to five accounts, and the final account is legally owned by somebody else. Then three conditions: every transfer under ten thousand, at least three of them, and more than twenty thousand in total.

`relationships(path)[1..-1]` drops the `CONTROLS` at the front and the `OWNED_BY` at the back, leaving only the transfers to test and sum.

> **What you should see.** Three chains.
>
> | Suspect | Beneficiary | Total moved | Transfers | Hops |
> |---|---|---|---|---|
> | John Doe | Kevin Garcia | 37,200 | 9800, 9500, 9200, 8700 | 4 |
> | John Doe | Rachel Patterson | 34,300 | 9200, 8900, 8400, 7800 | 4 |
> | John Doe | Rachel Patterson | 29,000 | 8500, 7200, 6800, 6500 | 4 |

**Now look carefully at the transfer amounts.** Every single one sits between 6,500 and 9,800, which is to say every one is below the ten thousand reporting threshold.

**Nothing here is illegal on its own.** Each transfer is an ordinary payment under the threshold, made between accounts that exist for legitimate reasons. **The crime is the shape, and the shape exists only in the relationships.** No rule applied to rows of the transactions table finds this, however clever the rule is, because no row is suspicious.

That is the strongest argument for graph thinking in this lab, and it is the abstraction worth carrying. Ask yourself where else a pattern lives in the connections rather than in the values. Circular trading in market surveillance. Split invoicing in procurement fraud. Cyclical dependencies in data lineage. Repeated referral loops in a care pathway.

### Why there is no SQL version here

The earlier comparisons showed you the SQL. For this one there is nothing reasonable to show, and that is the point.

To express this pattern relationally you would need a recursive CTE walking up to five account hops, a self-join per hop, an aggregate accumulated across a variable-length path, the threshold test applied to every intermediate transfer but not to the first or last relationship, and manual reconstruction of the path so you can report the individual amounts. It comes to somewhere past a hundred and fifty lines, it degrades sharply past three hops, and in practice teams avoid the whole thing by pre-computing materialised views for the specific hop counts they expect. **Which means the pattern they did not anticipate is the one they do not find.**

The Cypher is fifteen lines and the hop count is a parameter.

Run block **3.7** to see the same result as a picture.

## 2.7: Does the index get used?

Run block **3.8**.

> **What you should see.** `NodeIndexSeek` in the execution plan.

If it said `NodeByLabelScan` it would be reading all fifteen Person nodes to find one. On fifteen nodes it makes no difference. On fifteen million that is the difference between two milliseconds and two minutes. Same lesson as any database, and the reason you created the indexes first.

---

# Part 3: Graph algorithms (25 minutes)

## 3.1: Projections

Run blocks **4.1** through **4.4**.

**This is the one concept people get wrong, so read it twice.** The Graph Data Science library does not run on your database. It runs on an **in-memory projection**, which is a snapshot you build for one specific question.

You are building two, because there are two different questions:

- **`people`**: Person nodes only, three social relationship types, all **undirected**. For centrality and community detection.
- **`money`**: Persons and Accounts, financial relationships, direction **preserved**. For path finding.

> **What you should see.** `people` with **15 nodes and 92 relationships**. There are 46 edges, counted twice because you asked for `UNDIRECTED`; the algorithms need to traverse both ways.

> **The trap to remember.** A projection is a snapshot taken at the moment you create it. Change a property in the database afterwards and the projection does not see it. You must **drop and rebuild**. This is the single most common cause of "my GDS results look wrong".

## 3.2: Run the algorithms

Run the six statements in block **4.5**, one at a time, then block **4.6**.

**The pattern here is the important part.** Each algorithm **writes** its result to a node property. Then you read them all back in a single `MATCH`. Write, then read once.

**Why not chain them together?** Because `CALL gds.a.stream(...)` followed by `CALL gds.b.stream(...)` in one query re-runs the second algorithm once for every row of the first. On fifteen nodes that is fine and you will not notice. On a real graph it is a cartesian product and it never finishes. It is the classic tutorial pattern that dies in production.

Four of these six you met yesterday: degree, closeness, betweenness and eigenvector. Two are new: **PageRank**, which is eigenvector's practical cousin and always converges, and **Louvain**, which finds communities.

> **Before you look at the results, predict.** Who do you think will have the highest betweenness centrality? Write down a name.

> **What you should see.** The table ordered by betweenness, with roughly these at the top and bottom:
>
> | Person | Status | Role | Degree | Betweenness |
> |---|---|---|---|---|
> | Sarah Kim | ASSOCIATE | Cell Leader | 20 | ~16.8 |
> | Tommy Barnes | ASSOCIATE | Lieutenant | 17 | ~9.3 |
> | Elena Popov | ASSOCIATE | Operative | 3 | ~5.7 |
> | ... | | | | |
> | **John Doe** | **KNOWN_OFFENDER** | **Boss** | 15 | **~3.1** |
> | **Carlos Mendez** | **KNOWN_OFFENDER** | **Boss** | 5 | **~2.1** |
>
> Exact values vary slightly by GDS version. The ranking is what matters.

**Stop and look at the bottom two rows.** The two bosses have almost the lowest betweenness in the network. The highest belongs to an associate. **Position beats role**, and that is the finding of the whole session. The person who holds a network together is rarely the person with the title.

## 3.3: A trap in the degree column

Run block **4.7**.

> **What you should see.** John Doe's degree is **15**, but he has only **3** distinct neighbours.

Why? The projection kept all eleven parallel `CALLED` relationships between him and Sarah Kim. So **degree here is measuring call volume, not connectivity.**

Neither number is wrong. They answer different questions, and you have to know which one you asked. **What you put into the edge decides what the measure means.** If you want connectivity rather than volume, aggregate the calls before projecting.

## 3.4: The hidden broker

Run block **4.8**.

> **What you should see.** **Sarah Kim** at the top, well clear of everyone else.

Her status is `ASSOCIATE`. She is not a known offender and not a boss. She is the only person with a direct line to **both** bosses, which is why every path between the two organisations runs through her. In an investigation she is the highest-value surveillance target and she is not on anyone's list.

**This is the query to take back to work.** In your own graph, that same question finds the person, the module, or the transformation stage that nobody flagged because it has no title attached.

## 3.5: Communities and isolates

Run blocks **4.9**, **4.10** and **4.11**.

> **What you should see** from Louvain: three real cells plus three singletons.
>
> - Carlos Mendez, Maria Vasquez, **Sarah Kim**
> - John Doe, Tommy Barnes, Elena Popov, Mike Roberts, Nina Davis
> - Anna Petrov, David Wong, Lisa Johnson, Robert Clark
> - James Chen, Rachel Patterson and Kevin Garcia, each alone

**Notice where Sarah Kim was placed.** She is assigned to Carlos's cell, and her most frequent contact by a wide margin is John Doe in the other cell. **That is what a bridge looks like in community terms:** assigned to one group, functioning across two.

Then the components, and block 4.11.

> **What you should see.** One connected group of 12, and **three people with no social connections at all**: James Chen, Rachel Patterson and Kevin Garcia. Their closeness and eigenvector scores are zero.

A tutorial would call that a data quality problem. **It is not. It is the design.** Those three are the money mule and the two beneficiaries. A laundering network deliberately keeps the beneficiary socially disconnected from the criminal, because a social link is exactly what an investigator looks for. They exist only in the financial graph.

**The lesson for your own work is bigger than this dataset.** A node with no edges in one projection may be central in another. **Which graph you chose to build decides who is invisible.**

## 3.6: Similarity and a picture

Run block **4.12**, then **4.13**. In the Graph tab, size the nodes by `betweenness` and watch Sarah Kim grow while the bosses shrink.

---

# Part 4: What if we remove her? (10 minutes)

A common claim about betweenness is that removing the top broker fragments the network. Let us test it rather than believe it.

Run blocks **5.1** through **5.4**.

**The technique is worth noting**: tag everyone except the target with a temporary label, project on that label, rerun the algorithm. Simple, reversible, and nothing is deleted.

> **Before you run it, predict.** Does the network break into pieces?

> **What you should see.**
>
> - **It does not fragment.** Still one connected group, now of eleven, plus the same three isolates as before.
> - **The paths get longer.** Average shortest path rises from about 1.88 to about 2.16, and the diameter from 3 to 4.
> - **Tommy Barnes inherits the brokerage at roughly 20.7**, which is *higher* than Sarah Kim's original 16.8.

**So betweenness correctly identified a genuine chokepoint, and removing it did not disrupt the network.** It made everything slower and handed the role to the next person along.

Two things follow, and they matter more than the numbers.

- **The measure was right. A claim built on it was not.** Betweenness measures share of shortest paths, not structural necessity. If you want to know about disruption, measure disruption: the change in average path length, or who rises to replace the target. Do not assume it from the metric that identified them.
- **Removing either boss barely moves the network at all.** Average path length goes from 1.88 to about 1.91. So this network can survive losing its leadership and cannot easily survive losing its connectors. That is a real operational insight, and you can only get it by testing.

> **Go further.** Edit block 5.1 to exclude Tommy Barnes instead, and rerun. Then try removing both him and Sarah Kim. At what point does it actually fragment?

---

# Part 5: The query you should argue about (10 minutes)

Run block **6.1**. Read the output before you read on.

**This is taken from published tutorial material, under the heading "Predictive Policing".** It takes people whose recorded status is `CLEAN`, matches them against the connection patterns of known offenders, and returns the string `RECOMMEND INVESTIGATION`.

Nobody in that output has done anything. The result is generated entirely from who they happen to know.

Four questions. They are the point of the exercise, and there is no key at the back.

- **What were the labels?** `KNOWN_OFFENDER` is a record of who has previously been investigated and charged. So a model trained on it predicts **past policing activity**, not crime. Every bias in historical enforcement comes through intact and arrives wearing the authority of an algorithm.
- **Who bears the cost of a false positive?** A named individual with no record, who will never know they were flagged and has no route to contest it.
- **Would removing a protected attribute fix it?** No. Network position correlates with neighbourhood, which correlates with almost everything. **Here the proxy is the graph itself**, and you cannot drop a column to get rid of it.
- **Who signs this off, and against what standard?** Most organisations have no answer. If you work in assurance or governance, this is your question.

**Notice what actually changed.** That query uses `gds.nodeSimilarity`, the same algorithm you ran two blocks earlier to find people with overlapping contacts. The computation is identical. **What changed is the sentence attached to the output.**

One comparison worth sitting with. The money laundering query found a pattern in **what people did**: specific transfers, specific amounts, specific accounts. This query found a pattern in **who people know**. The first is evidence. The second is association, and both arrive in the same tidy table.

**Legality, capability and appropriateness are three separate tests.** Every technique in this lab is neutral. None of the decisions about how to use them are.

Finally, run block **7** to drop the projections and tidy up.

---

# Take it back to your own work

The whole point of the day is the translation. Here is the starting grid.

| | Nodes | Edges | What betweenness tells you |
|---|---|---|---|
| **Data lineage** | Source systems, transformation stages, target applications | Directed dependency | Which transformation's failure propagates furthest, so where assurance effort belongs |
| **Code and tests** | Modules, tests, requirements | Imports, calls, coverage | Which component's breakage blocks the most test paths |
| **Care pathways** | Care settings, providers | Referrals and transfers, weighted by volume | Which handover point most journeys must pass through, so where the drop-out happens |
| **Provider networks** | Units, trusts | Transfers, referrals | Whose loss fragments the regional network |
| **People and teams** | Staff | Who you go to when something is going wrong | Who reaches both halves of the organisation |

**Building the edge list is most of the work,** and two patterns cover nearly everything:

- **The relationship is already in the row.** A refers to B. Module X imports Y. Stage P writes object Q. Select two columns, aggregate for a weight, done.
- **You derive it from co-occurrence.** Two conditions in the same patient record. Two tests touching the same module. That is a self-join on the shared key, and it produces the same object as a co-occurrence matrix with one axis relabelled.

**A practical note for anyone whose data is locked down.** A lineage graph can often be built from platform metadata rather than from the data itself. No patient records, no customer rows, nothing sensitive leaves anywhere. The nodes are object names and the edges are dependencies. That is frequently the fastest route to a useful graph in a governed environment.

**The closing question, and it is the one worth carrying.** Everything else this week treated each record as independent: one patient, one test, one transaction. Today the relationships were the data and the records were almost incidental. **Where in your work are you modelling entities in isolation when the connections between them are the thing that matters?**

---

# If something goes wrong

| Symptom | Cause and fix |
|---|---|
| `Couldn't load the external resource` | The URL is unreachable or the file is not in the import folder. Switch to Route B, or check the filename spelling exactly, including case. |
| `Unknown function 'gds.version'` | The plugin is not installed, or the instance was not restarted after installing it. |
| `There is no procedure with the name gds.closeness` | Your build has it as `gds.beta.closeness`. Try that, or skip it. Nothing later depends on it. |
| "No changes, no records" after a relationship load | The `MATCH` found no node with that name. Run block 1.4 first: if statuses are null, the node load went wrong and everything downstream will fail silently. |
| Counts come back as zero, or a query returns nothing after a clean load | You are on the wrong database. Check the selector at the top of the query window reads `crimenetdb`, not `neo4j`. |
| A graph projection already exists | `CALL gds.graph.drop('name', false);` The `false` means do not error if it is missing. |
| You ran a load twice | The constraints blocked duplicate nodes and every relationship load uses `MERGE`, so you are safe. If in doubt, run block 0.1 and start again. The full load takes under a minute. |
| Syntax error on a quote mark | You copied code out of a PDF or Word document, which converts straight quotes to curly ones. Copy from `lab-queries.cypher` instead. |

---

# A short glossary

- **Node.** A thing. A person, an account, a module, a data object.
- **Relationship.** A connection between two nodes. Always directed in Neo4j, even when the direction means nothing.
- **Label.** A node's type, written `:Person`. A node can have several.
- **Property.** A key and value on a node or a relationship, such as `name` or `amount`.
- **Cypher.** Neo4j's query language. You draw the pattern you are looking for and it finds every match.
- **Traversal.** Following relationships from node to node. `*1..3` means follow between one and three of them.
- **Projection.** An in-memory snapshot of part of your graph, built so an algorithm can run over it.
- **Degree.** How many relationships a node has.
- **Betweenness.** What share of all shortest paths in the network run through this node.
- **Closeness.** How few hops it takes this node to reach everyone else.
- **PageRank.** Recursive importance. You matter if the people pointing at you matter.
- **Community detection.** Finding the natural groups. Louvain is the usual first choice.
- **Idempotent.** Safe to run more than once with the same result. `MERGE` gives you this; `CREATE` does not.

---

# Where to go next, all free

- **Neo4j Desktop.** What you used today. Local, free, includes the Graph Data Science plugin.
- **Neo4j Sandbox.** Browser based, nothing to install, GDS already there. Useful when you cannot install software.
- **GraphAcademy.** Free, interactive, hands-on courses, including a path aimed at data scientists.
- **The GDS manual.** Every algorithm, with worked examples and guidance on when each one is appropriate.
