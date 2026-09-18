// ============================================================================
//  GRAPH DATA SCIENCE LAB - CRIMINAL NETWORK ANALYSIS
//  Run these blocks in order in Neo4j Browser / Query.
//  Each block is separated by a blank line and ends with a semicolon.
//
//  ROUTE A - LOAD FROM THE REPOSITORY (default, nothing to change)
//  The URLs below are live and ready to run. Copy and paste as-is.
//  Base URL: https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/
//  These resolve only while the repository is public, so download the CSVs
//  during the session if you want to repeat the lab later.
//
//  ROUTE B - LOAD FROM LOCAL FILES (if the URLs are blocked on your machine)
//  Put the 8 CSVs in the instance's import folder, then one find-and-replace:
//    FIND:     https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/
//    REPLACE:  file:///
//  So 'https://raw.../persons.csv' becomes 'file:///persons.csv'.
// ============================================================================


// ----------------------------------------------------------------------------
// PART 0 - RESET AND CONSTRAINTS
// ----------------------------------------------------------------------------

// 0.1 Clean slate. Safe to re-run at any point.
MATCH (n) DETACH DELETE n;

// 0.2 Constraints first. A unique constraint also creates an index, and it
//     makes a duplicate load fail loudly instead of silently duplicating.
CREATE CONSTRAINT person_id IF NOT EXISTS
FOR (p:Person) REQUIRE p.id IS UNIQUE;

CREATE CONSTRAINT account_number IF NOT EXISTS
FOR (a:Account) REQUIRE a.accountNumber IS UNIQUE;

// 0.3 Plain indexes on the properties we filter and match on.
CREATE INDEX person_name IF NOT EXISTS FOR (p:Person) ON (p.name);
CREATE INDEX person_status IF NOT EXISTS FOR (p:Person) ON (p.status);

// 0.4 Confirm.
SHOW CONSTRAINTS;


// ----------------------------------------------------------------------------
// PART 1 - LOAD NODES
// ----------------------------------------------------------------------------

// 1.1 People. MERGE on the business key, SET the rest.
//     trim() everywhere because persons.csv and accounts.csv were saved with
//     Windows line endings while the relationship files were not.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/persons.csv' AS row
MERGE (p:Person {id: trim(row.id)})
SET p.name             = trim(row.name),
    p.status           = trim(row.status),
    p.role             = trim(row.role),
    p.phone            = trim(row.phone),
    p.lastKnownAddress = trim(row.lastKnownAddress),
    p.dateOfBirth      = CASE
                           WHEN row.dateOfBirth IS NULL OR trim(row.dateOfBirth) = ''
                           THEN null
                           ELSE date(trim(row.dateOfBirth))
                         END;

// 1.2 Accounts.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/accounts.csv' AS row
MERGE (a:Account {accountNumber: trim(row.accountNumber)})
SET a.bank    = trim(row.bank),
    a.balance = toInteger(trim(row.balance)),
    a.status  = trim(row.status);

// 1.3 Node counts. Expect Account 12, Person 15.
MATCH (n)
RETURN labels(n)[0] AS NodeType, count(*) AS Count
ORDER BY NodeType;

// 1.4 *** THE CHECK THAT MATTERS *** Expect six status values, no nulls.
//     CLEAN 5 | ASSOCIATE 4 | KNOWN_OFFENDER 2 | BENEFICIARY 2
//     PERSON_OF_INTEREST 1 | MONEY_MULE 1
//     If you see a null row here, STOP and fix the load before going on.
MATCH (p:Person)
RETURN p.status AS Status, count(*) AS People
ORDER BY People DESC, Status;

// 1.5 Who has incomplete records? Expect 3 people, with Address showing null.
MATCH (p:Person)
WHERE p.dateOfBirth IS NULL
RETURN p.name             AS Person,
       p.status           AS Status,
       p.role             AS Role,
       p.lastKnownAddress AS Address;

// 1.6 And the records that ARE complete. Read the Address column.
MATCH (p:Person)
WHERE p.lastKnownAddress IS NOT NULL
RETURN p.name             AS Person,
       p.status           AS Status,
       p.lastKnownAddress AS Address
ORDER BY p.status, p.name;


// ----------------------------------------------------------------------------
// PART 2 - LOAD RELATIONSHIPS
// ----------------------------------------------------------------------------

// 2.1 COMMANDS - organisational hierarchy (directed, and direction matters).
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/commands_relationships.csv' AS row
MATCH (s:Person {name: trim(row.source_name)})
MATCH (t:Person {name: trim(row.target_name)})
MERGE (s)-[r:COMMANDS]->(t)
ON CREATE SET r.since = date(trim(row.since));

// 2.2 KNOWS - social ties. Stored with a direction, queried without one.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/knows_relationships.csv' AS row
MATCH (a:Person {name: trim(row.person1_name)})
MATCH (b:Person {name: trim(row.person2_name)})
MERGE (a)-[r:KNOWS]->(b)
ON CREATE SET r.since = date(trim(row.since));

// 2.3 CALLED - one relationship per call, keyed on timestamp so a repeat
//     run cannot duplicate the call log.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/called_relationships.csv' AS row
MATCH (caller:Person {name: trim(row.caller_name)})
MATCH (recipient:Person {name: trim(row.recipient_name)})
MERGE (caller)-[r:CALLED {timestamp: datetime(trim(row.timestamp))}]->(recipient)
ON CREATE SET r.duration = toInteger(trim(row.duration));

// 2.4 CONTROLS - person can transact on the account.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/controls_relationships.csv' AS row
MATCH (p:Person {name: trim(row.person_name)})
MATCH (a:Account {accountNumber: trim(row.account_number)})
MERGE (p)-[r:CONTROLS]->(a)
ON CREATE SET r.since = date(trim(row.since));

// 2.5 OWNED_BY - legal owner, who may have no access at all.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/owned_by_relationships.csv' AS row
MATCH (a:Account {accountNumber: trim(row.account_number)})
MATCH (p:Person {name: trim(row.person_name)})
MERGE (a)-[:OWNED_BY]->(p);

// 2.6 TRANSFERRED_TO - money movement, keyed on date.
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/qalhata/GraphAnalyticsPractice/main/transferred_to_relationships.csv' AS row
MATCH (s:Account {accountNumber: trim(row.source_account)})
MATCH (t:Account {accountNumber: trim(row.target_account)})
MERGE (s)-[r:TRANSFERRED_TO {date: datetime(trim(row.date))}]->(t)
ON CREATE SET r.amount      = toInteger(trim(row.amount)),
              r.description = trim(row.description);

// 2.7 Relationship counts. Expect CALLED 26, TRANSFERRED_TO 12,
//     COMMANDS 10, KNOWS 10, CONTROLS 3, OWNED_BY 2. Total 63.
MATCH ()-[r]->()
RETURN type(r) AS RelationshipType, count(*) AS Count
ORDER BY Count DESC;

// 2.8 Total. Expect 63.
MATCH ()-[r]->()
RETURN count(r) AS TotalRelationships;


// ----------------------------------------------------------------------------
// PART 3 - CYPHER: ASKING QUESTIONS OF A GRAPH
// ----------------------------------------------------------------------------

// 3.1 Look at it. Switch to the Graph tab.
MATCH (p:Person)-[r]-(other)
RETURN p, r, other
LIMIT 50;

// 3.2 Who controls accounts, and what is their status?
//     Expect John Doe (KNOWN_OFFENDER), Carlos Mendez (KNOWN_OFFENDER),
//     James Chen (MONEY_MULE).
MATCH (p:Person)-[:CONTROLS]->(a:Account)
RETURN p.name AS Person, p.status AS Status, p.role AS Role,
       collect(a.accountNumber) AS Accounts;

// 3.3 Two degrees of separation from John Doe.
MATCH path = (suspect:Person {name: 'John Doe'})-[:KNOWS|CALLED*1..2]-(associate:Person)
WHERE associate <> suspect
RETURN associate.name   AS Associate,
       associate.status AS Status,
       min(length(path)) AS Degrees
ORDER BY Degrees, Associate;

// 3.4 The org chart, four levels deep, with the chain of command.
MATCH path = (boss:Person {name: 'Carlos Mendez'})-[:COMMANDS*1..4]->(sub:Person)
RETURN sub.name AS Member,
       sub.role AS Role,
       length(path) AS Level,
       [n IN nodes(path)[1..-1] | n.name] AS ChainOfCommand
ORDER BY Level, Member;

// 3.5 High-frequency call pairs. Expect exactly two, both at 11 calls.
MATCH (a:Person)-[c:CALLED]->(b:Person)
WITH a, b, count(c) AS calls, sum(c.duration) AS totalSeconds
WHERE calls >= 10
RETURN a.name AS Caller, b.name AS Recipient,
       calls AS Calls,
       totalSeconds AS TotalSeconds,
       toInteger(round(1.0 * totalSeconds / calls)) AS AvgSeconds
ORDER BY calls DESC;

// 3.6 THE SHOWPIECE - smurfing detection.
//     Many small transfers, each under the 10,000 reporting threshold,
//     chained through intermediate accounts, ending with a different
//     beneficiary. Expect 3 chains, 29,000 / 34,300 / 37,200.
MATCH path = (criminal:Person {status: 'KNOWN_OFFENDER'})
             -[:CONTROLS]->(:Account)
             -[:TRANSFERRED_TO*1..5]->(dest:Account)
             -[:OWNED_BY]->(beneficiary:Person)
WHERE criminal <> beneficiary
  AND ALL(rel IN relationships(path)[1..-1] WHERE rel.amount < 10000)
  AND size(relationships(path)[1..-1]) >= 3
WITH criminal, beneficiary,
     [rel IN relationships(path)[1..-1] | rel.amount] AS amounts,
     reduce(total = 0, rel IN relationships(path)[1..-1] | total + rel.amount) AS totalMoved
WHERE totalMoved > 20000
RETURN criminal.name    AS Suspect,
       beneficiary.name AS Beneficiary,
       totalMoved       AS TotalMoved,
       amounts          AS Transfers,
       size(amounts)    AS Hops
ORDER BY totalMoved DESC;

// 3.7 The same thing as a picture. Switch to the Graph tab.
MATCH path = (:Person {status: 'KNOWN_OFFENDER'})
             -[:CONTROLS]->(:Account)
             -[:TRANSFERRED_TO*1..5]->(:Account)
             -[:OWNED_BY]->(:Person)
RETURN path;

// 3.8 Does the index get used? Look for NodeIndexSeek, not NodeByLabelScan.
PROFILE
MATCH (p:Person {name: 'John Doe'})
RETURN p;


// ----------------------------------------------------------------------------
// PART 4 - GRAPH DATA SCIENCE
// ----------------------------------------------------------------------------

// 4.1 Confirm the plugin. Expect 2.x or higher.
RETURN gds.version() AS GDSVersion;

// 4.2 Project the social network. Person nodes only, three relationship
//     types, all undirected. Expect 15 nodes and 92 relationships
//     (46 edges counted in both directions).
CALL gds.graph.drop('people', false);

CALL gds.graph.project(
  'people',
  'Person',
  {
    KNOWS:    {orientation: 'UNDIRECTED'},
    CALLED:   {orientation: 'UNDIRECTED'},
    COMMANDS: {orientation: 'UNDIRECTED'}
  }
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// 4.3 Project the money network separately. Different question, different graph.
CALL gds.graph.drop('money', false);

CALL gds.graph.project(
  'money',
  ['Person', 'Account'],
  {
    CONTROLS:       {orientation: 'NATURAL'},
    TRANSFERRED_TO: {orientation: 'NATURAL', properties: 'amount'},
    OWNED_BY:       {orientation: 'NATURAL'}
  }
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// 4.4 List what is projected.
CALL gds.graph.list()
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// 4.5 Write every metric to node properties. One algorithm per statement.
//     This is the correct pattern: write, then read back once.
CALL gds.degree.write('people', {writeProperty: 'degree'})
YIELD nodePropertiesWritten RETURN nodePropertiesWritten;

CALL gds.betweenness.write('people', {writeProperty: 'betweenness'})
YIELD nodePropertiesWritten RETURN nodePropertiesWritten;

CALL gds.closeness.write('people', {writeProperty: 'closeness'})
YIELD nodePropertiesWritten RETURN nodePropertiesWritten;

CALL gds.eigenvector.write('people', {writeProperty: 'eigenvector', maxIterations: 50})
YIELD nodePropertiesWritten RETURN nodePropertiesWritten;

CALL gds.pageRank.write('people', {writeProperty: 'pagerank', maxIterations: 20, dampingFactor: 0.85})
YIELD nodePropertiesWritten RETURN nodePropertiesWritten;

CALL gds.louvain.write('people', {writeProperty: 'community'})
YIELD communityCount, modularity RETURN communityCount, modularity;

// 4.6 Read them all back in ONE query. This is the payoff.
MATCH (p:Person)
RETURN p.name   AS Person,
       p.status AS Status,
       p.role   AS Role,
       toInteger(p.degree)        AS Degree,
       round(p.betweenness, 1)    AS Betweenness,
       round(p.closeness, 3)      AS Closeness,
       round(p.eigenvector, 3)    AS Eigenvector,
       round(p.pagerank, 3)       AS PageRank,
       p.community                AS Cell
ORDER BY Betweenness DESC;

// 4.7 Degree is counting parallel call edges. Compare distinct neighbours.
//     John Doe: degree 15, but only 3 distinct people.
MATCH (p:Person)
OPTIONAL MATCH (p)-[:KNOWS|CALLED|COMMANDS]-(other:Person)
WITH p, count(DISTINCT other) AS distinctNeighbours
RETURN p.name AS Person,
       toInteger(p.degree) AS DegreeWithParallelEdges,
       distinctNeighbours  AS DistinctNeighbours,
       round(p.betweenness, 1) AS Betweenness
ORDER BY DegreeWithParallelEdges DESC;

// 4.8 The hidden broker. High betweenness, not flagged as an offender.
MATCH (p:Person)
WHERE p.betweenness > 0 AND p.status <> 'KNOWN_OFFENDER'
RETURN p.name AS Person, p.status AS Status, p.role AS Role,
       round(p.betweenness, 1) AS Betweenness
ORDER BY p.betweenness DESC
LIMIT 5;

// 4.9 Communities. Expect three real cells plus three isolated singletons.
MATCH (p:Person)
WHERE p.community IS NOT NULL
RETURN p.community AS Cell, count(*) AS Size, collect(p.name) AS Members
ORDER BY Size DESC;

// 4.10 Connected components. Expect one group of 12 and three singletons.
CALL gds.wcc.stream('people')
YIELD nodeId, componentId
RETURN componentId AS Component,
       count(*) AS Size,
       collect(gds.util.asNode(nodeId).name) AS Members
ORDER BY Size DESC;

// 4.11 Who are the three isolates, and why does that matter?
MATCH (p:Person)
WHERE NOT (p)-[:KNOWS|CALLED|COMMANDS]-()
OPTIONAL MATCH (p)-[fin:CONTROLS]->(a:Account)
OPTIONAL MATCH (owned:Account)-[:OWNED_BY]->(p)
RETURN p.name AS Person, p.status AS Status, p.role AS Role,
       collect(DISTINCT a.accountNumber) AS Controls,
       collect(DISTINCT owned.accountNumber) AS Owns;

// 4.12 Who behaves like whom, based on shared connections?
CALL gds.nodeSimilarity.stream('people', {topK: 3})
YIELD node1, node2, similarity
WITH gds.util.asNode(node1) AS a, gds.util.asNode(node2) AS b, similarity
WHERE similarity > 0.4
RETURN a.name AS Person1, a.status AS Status1,
       b.name AS Person2, b.status AS Status2,
       round(similarity, 3) AS Similarity
ORDER BY similarity DESC
LIMIT 10;

// 4.13 Visualise, then size the nodes by betweenness in the Graph tab.
MATCH (p:Person)-[r:KNOWS|CALLED|COMMANDS]-(other:Person)
RETURN p, r, other;


// ----------------------------------------------------------------------------
// PART 5 - DISRUPTION: WHAT IF WE REMOVE THE TOP BROKER?
// ----------------------------------------------------------------------------

// 5.1 Tag everyone except the top broker with a temporary label.
MATCH (p:Person)
WHERE p.name <> 'Sarah Kim'
SET p:Remaining;

// 5.2 Project the reduced network.
CALL gds.graph.drop('disrupted', false);

CALL gds.graph.project(
  'disrupted',
  'Remaining',
  {
    KNOWS:    {orientation: 'UNDIRECTED'},
    CALLED:   {orientation: 'UNDIRECTED'},
    COMMANDS: {orientation: 'UNDIRECTED'}
  }
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// 5.3 Did it fragment? Compare against 4.10. It does NOT.
CALL gds.wcc.stream('disrupted')
YIELD nodeId, componentId
RETURN componentId AS Component, count(*) AS Size,
       collect(gds.util.asNode(nodeId).name) AS Members
ORDER BY Size DESC;

// 5.4 Who becomes the broker instead?
CALL gds.betweenness.stream('disrupted')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).name AS Person,
       gds.util.asNode(nodeId).status AS Status,
       round(score, 1) AS NewBetweenness
ORDER BY score DESC
LIMIT 5;

// 5.5 Tidy up the temporary label and the projection.
MATCH (p:Remaining) REMOVE p:Remaining;
CALL gds.graph.drop('disrupted');


// ----------------------------------------------------------------------------
// PART 6 - THE ETHICS CASE (run it, then argue about it)
// ----------------------------------------------------------------------------

// 6.1 "Predictive policing": people with no record who resemble offenders.
//     Read the output, then ask what the labels were and who made them.
CALL gds.nodeSimilarity.stream('people', {topK: 5})
YIELD node1, node2, similarity
WITH gds.util.asNode(node1) AS a, gds.util.asNode(node2) AS b, similarity
WHERE a.status = 'KNOWN_OFFENDER'
  AND b.status = 'CLEAN'
  AND similarity > 0.2
RETURN a.name AS KnownOffender,
       b.name AS FlaggedIndividual,
       b.status AS TheirCurrentStatus,
       round(similarity, 3) AS BehaviourMatch,
       'RECOMMEND INVESTIGATION' AS SystemRecommendation
ORDER BY similarity DESC;


// ----------------------------------------------------------------------------
// PART 7 - CLEANUP
// ----------------------------------------------------------------------------

CALL gds.graph.list() YIELD graphName
CALL gds.graph.drop(graphName) YIELD graphName AS dropped
RETURN dropped;
