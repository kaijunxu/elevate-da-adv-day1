# Business Requirements Document (BRD) — Cymbal Retail 

**Customer Use Case**: Cymbal Retail — Agentic AI & Data Platform Modernization Initiative  
**Document Owner**: Chief Information Officer (CIO), Director of Retail Data Engineering, & GCP Account Team  
**Document Version**: 3.0

---

## 1\. Executive Summary & Pilot Objectives

Cymbal Retail is a global electronics retailer operating 500+ physical storefronts and a global e-commerce portal. Currently running on an AWS & Databricks data platform, they face escalating cross-cloud data egress fees, high Apache Spark infrastructure management overhead, 24-hour batch latencies that create inventory blind spots and checkout shrinkage as well as inability to have agentic workflows on multi-modal data sources (structured \+ unstructured).

The objective of this pilot is to deploy a Google Cloud Agentic Data Cloud platform solution that gives them an open-format supported  lakehouse federation, streaming intelligence, and a conversational AI self-service analytics portal. 

* **Eliminate Data Silos:** Transition from fragmented, duplicated reporting tables to a unified, open data lakehouse architecture that enables in-place querying across retail domains without physical data replication or staging.  
* **Achieve Real-Time Operational Visibility:** Replace 24-hour batch reporting latencies with continuous streaming intelligence, providing store managers and POS checkout applications with near real time lookups for order anomalies and cashier promotion abuse.  
* **Unlock Insights from Dark Data:** Ingest and vectorize dark unstructured PDF POS technical manuals and warranty documents into an interactive, grounded conversational knowledge base for instant shop-floor hardware troubleshooting.  
* **Enable Conversational Self-Service Analytics:** Empower store managers and supply chain planners to query net profit margins, available-to-promise (ATP) inventory, and warranty triaging using natural language without writing complex SQL or navigating fragmented BI tools.  
* **Validate Multi-System Orchestration:** Demonstrate the capability to chain actions across structured historical data, real-time alert streams, and unstructured technical manuals to solve complex retail workflows (e.g., checkout warranty triage, order anomaly risk detection), serving as a critical evaluation benchmark for prototype success before scaling.  
* **Collaborative Notebook Workspace**: interactive, multi-language notebooks for data science prototyping.  
* **Open Storage Paradigm**: open-format tables (Apache Iceberg) on cloud object storage, no proprietary lock-in.  
* **Ensure Enterprise Governance & Security:** Maintain 100% visibility over data certification and lineage, for e.g., enforce row-level security per Store Manager, and automatically mask customer payment card numbers across all conversational turns and query logs.

---

## 2\. Project Scope (Pilot)

### 2.1. Functional Scope 

* Conversational User Interface (UI): Web-based chat portal allowing store staff to query structured, unstructured, and live streaming data using natural language.  
* Lakehouse Federation & Serverless Spark: Zero-copy querying of S3 Iceberg tables via Cross-cloud lakehouse, and Serverless Spark ETL for nightly inventory reconciliation.  
* Streaming Intelligence: Real time ingestion of POS transactions, sliding-window cashier promotion override aggregations, low-latency real-time transaction anomaly and promotion abuse scoring, and near real time point lookups.  
* Document Q\&A (RAG): Grounded Q\&A over PDF product catalogs, system repair manuals, and warranty documents with source citations.  
* Enterprise Governance & Security: Knowledge Catalog metadata, row-level security per Store Manager token, and dynamic payment card PII masking.

### 2.2. Data Scope 

* Unstructured Documents: PDF POS terminal manuals, and warranty documents in an AWS S3 bucket.  
* Batch data:  
  * Retail Iceberg Dimensions & Fact Tables (via REST Catalog): Customer, Product, Demographics, Supplier, Inventory & Sales order data (Silver conformed fact table)   
  * Gold aggregate fact table (via REST Catalog): Containing daily store metrics.  
  * POS Transactional Telemetry: Daily POS transaction dumps. You will need to build data pipelines on this data for downstream use.   
* Real time POS stream: A Kafka topic containing POS transactions, sent in real-time from 50 stores. Transactions are sent as JSON strings with identifiers for store, cashier, POS terminal and customer, item basket details and payment details.

### 2.3. Out of Scope for Pilot

* Direct Multi-Cloud Write-Backs: All connections to AWS S3 and regional store databases are strictly read-only.  
* Multi-Language & Telephony: Non-English languages, IVR, and VoIP telephony hooks are excluded.  
* Production Enterprise SSO Sync: Uses functional GCP test service accounts and mock JWT identity headers instead of live Okta/AD sync.

---

## 3\. Current State Architecture 

### 3.1. Core Systems & Platform Components

* Lakehouse Storage (AWS S3): Raw, semi-structured, and curated datasets in open Apache Iceberg format.  
* Batch & Interactive Compute: Databricks (on AWS) Spark clusters for nightly ETL; vectorized SQL engine for BI queries.  
* Unified Governance Catalog: AWS Glue Data Catalog managing schemas, tables, and column/row permissions.  
* Data Science Workspace: Collaborative Jupyter-style notebooks for demand forecasting prototyping.  
* Enterprise BI Layer: Tableau serving daily executive dashboards.

### 3.2. Core Operational Workloads

* POS Sales Deduplication & Aggregation: Ingests daily POS files from 500+ stores, reconciles promotional discounts, removes duplicate/late-arriving records, and emits flash sales summaries.  
* Nightly Inventory Conformance: Normalizes shelf and backroom stock counts across 500+ store locations into a single daily conformed snapshot.  
* Demand Forecasting ML Features: Distributed Spark jobs building customer feature tables for demand forecasting models.

### 3.3. End-to-End Current State Data Lineage

Operational POS logs, store inventories, and supplier PDFs flow through AWS S3 landing buckets into Medallion layers (Bronze, Silver, Gold), cataloged in AWS Glue Data Catalog, queried via the AWS SQL engine, and consumed by Tableau/Power BI dashboards.

---

## 4\. Pilot Use Cases and Interaction Examples

| Domain | Module | Use Case ID | Category | Triggering User Prompt (Example) | Primary Data Sources Involved | Expected Business & Agentic Outcome |
| :---- | :---- | :---- | :---- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---- | :---- |
| **Single**  | **Agent(Module 3\)** | **UC-1.1** | Unstructured Manual Q\&A (RAG) | • What is the field recovery procedure when our POS cashier terminal displays an error code?<br>• What is the immediate field recovery protocol when a cashier encounters an ERR-PAY-4001 EMV contactless payment freeze, and how do we ensure the customer is not double-charged?<br>• When a terminal displays error code ERR-SYNC-900, what supervisor sequence must be executed to resolve the problem? (Fallback testing) | Unstructured Technical Manuals (PDFs) in GCS bucket and linked object table with document chunks and embeddings in BigQuery | Agent retrieves relevant manual passages and generates a grounded diagnostic guide with clickable source citations (document name, page, and section header).<br>If question is not relevant or cannot be answered by the RAG agent the agent should perform a graceful fallback. |
| **Single** | **Agent(Module 3\)** | **UC-1.2** | Store Operations & Sales Analytics | • Are there any items with high intraday revenue but also high estimated cover hours? Or conversely, low-revenue items with critically low cover hours?<br>• What is the intraday gross revenue for Store 'STORE\_008', and how many total units of item 'prod\_4825' are currently on hand? | Curated Analytics Lakehouse & Central Business Glossary | Agent routes to the analytical SQL subagent, maps business terms via the central glossary, and delivers accurate sales KPIs and real-time inventory counts without formula hallucination. |
| **Single** | **Agent(Module 3\)** | **UC-1.3** | Live Operational Alert Lookup | • Are there any active order-anomaly alerts or cashier discount override flags reported at Store 41 in the last 24 hours? | Real-Time Operational Cache (Bigtable) | Agent executes a point lookup against Bigtable using a well-constructed row key filter and displays cashier override counts and active fraud flags in the last 24 hours. |
| **Multi-Domain Relational \+ RAG** | **Agent(Module 3\)** | **UC-2.1** | Customer Warranty Triage  | • Check transaction details for TXN-20260312-0015811 and show the warranty coverage policy for the purchased item.<br>• Customer CUST_02598 purchased an item at Store 6 using a Gift Card. Is their item covered under warranty? | Conformed Customer Lakehouse Tables, Unstructured Warranty Repository (PDFs in GCS and Object Table in BigQuery) | Multi-System Orchestration: Agent sequentially queries historical sales tables to resolve the transaction, product and loyalty tier, and searches warranty manuals for coverage rules—synthesizing a unified verdict |
| **Multi-Domain Streaming BQ table and Bigtable cache** | **Agent(Module 3\)** | **UC-2.2** | Intra-Day Cashier Risk vs. Nightly Audit | • What is Cashier CASH\_1190's live 1-hour override rate right now, compared to their daily override baseline? | Low-Latency Operational Cache (Sliding-Window Aggregates) in BigTable & Clean streaming POS tables(BigQuery) | Multi-System Orchestration: Agent fires parallel queries to Bigtable and BigQuery. |
| **Multi-Domain Streaming \+ Relational (DLP)** | **Agent(Module 3\)** | **UC-2.3** | Cashier Promotion Abuse Audit  | • Show cashiers with live promo override alerts today. Pull transaction history for the highest offender. | POS Anomaly Alerts (BigQuery) and POS Transactions (Cross-cloud Lakehouse) | Multi-System Orchestration: Agent sequentially queries anomaly alerts table to show all cashiers with alerts, then pulls transaction history from federated table for the highest offender. |
| **Multi Domain Graph \+ Relational** |  | **UC-2.4** | Supply Chain Traceability & Recall | • Identify all customers who purchased units from batch LOT-202607-PROD2-08, and retrieve their warranty certificate details.<br>• Identify all products that have active recalls or QA defects. List their batch IDs, root cause defect, the purchasing customer names, their phone numbers, and the store where they bought it.<br>• What is the total number of lots produced by each supplier, how many passed clean QA versus flagged for harmful materials, and what is their overall defect rate?<br>• Show me all batches manufactured by suppliers with risk score greater than 0.75, their certification status, and whether any of those lots were sold to consumers.<br>• Filter for Platinum and Gold loyalty members who purchased any recalled items so our VIP customer care team can reach out to them directly.<br>• List all clean production lots that passed QA inspections without defects, along with their supplier country and product name. | Supply chain traceability Graph (BigQuery), Key-value pairs extracted in a BQ Table from Warranty PDFs (GCS) | Allow analysts to ask questions of the graph dataset in BQ Notebook.<br>The agent built in Module 3 will not connect to the graph dataset. |

---

## 5\. Functional Requirements

### 5.1. AI Governance & Security Infrastructure

| Requirement ID | Requirement Name | Description |
| :---- | :---- | :---- |
| FR-1.1 | Central Managed Tool Gateway | All external tool invocations must route through a centralized gateway. Direct, unmanaged API calls are blocked. |
| FR-1.2 | Delegated End-User Identity Token Passing | Every query execution must pass the end-user's verified enterprise identity token to enforce row-level security (e.g., restricting Store Managers to their own store's data). |
| FR-1.3 | Verification of Conversation Safety | Intercept and block prompt injection, jailbreak attempts, and toxic/off-topic outputs using AI Guardrail tools. |
| FR-1.4 | Central Metadata & Policy Tagging | All conformed data assets must be registered in the central data catalog with certification tags (certified \= true) and column-level policy tags. |
| FR-1.5 | PII Masking | Integrate catalog policies to automatically redact customer payment card numbers (XXXX-XXXX-XXXX-9999) across all query logs and chat responses. |

### 5.2. Core Conversational Capabilities

| Requirement ID | Requirement Name | Description |
| :---- | :---- | :---- |
| FR-2.1 | Natural Language Understanding & Routing | Accurately parse user intent, typos, and conversational context, dynamically routing requests to specialized subagents or tools  |
| FR-2.2 | Multi-Turn Dialog & State Isolation | Maintain conversational state across multi-turn dialogues while guaranteeing strict session memory isolation between different user login sessions. |

### 5.3. Data Lakehouse Federation & Batch Processing

| Requirement ID | Requirement Name | Description & Operations |
| :---- | :---- | :---- |
| FR-3.1 | Cross-Cloud Lakehouse Federation | Configure secure connections to remote S3 Iceberg REST Catalogs, enabling execution of analytical queries in-place without physical data replication. |
| FR-3.2 | Serverless PySpark Normalization | Nightly batch ETL PySpark jobs for inventory reconciliation and sales deduplication must execute seamlessly, scaling compute to $0 when idle. |
| FR-3.3 | Native Vectorized Execution Engine | Query execution across large Iceberg fact tables must leverage a native vectorized execution engine, achieving \>=2x throughput over standard Java Spark engines. |

### 5.4. Streaming Intelligence & Low-Latency Serving

| Requirement ID | Requirement Name | Description & Operations |
| :---- | :---- | :---- |
| FR-4.1 | High-Throughput Streaming Ingestion | Ingest POS transactions from 50 stores in real-time, supporting ingestion in raw format from source systems and parsing to structured formats suitable for querying. |
| FR-4.2 | Resilient Sliding-Window Aggregations | Execute sliding-window aggregations (1-hour window) on cashier promotion overrides to feed ML model for cashier promotion abuse behavior. |
| FR-4.3 | Low-Latency Operational Cache | Persist calculated aggregations on cashier promotion overrides for automated remediation. |
| FR-4.4 | Low-Latency in-flight ML inferences | Deploy ML models to score transactions in-flight for possible order anomalies or cashier promotion abuse activity with \<50ms model latency. |

### 5.5. Technical Manual Q\&A (RAG System)

| Requirement ID | Requirement Name | Description & Operations |
| :---- | :---- | :---- |
| FR-5.1 | Document Vector Ingestion | Ingest, chunk, embed, and index approved PDF technical manuals and warranty policies into a vector DB. |
| FR-5.2 | Strict Grounding Safety Guardrail | If vector search returns chunks below a relevance score of 0.7, the agent must decline to answer: "I cannot find certified warranty or repair rules for this specific error in our technical repository." |
| FR-5.3 | Source Citations and Clicking | Every troubleshooting recommendation must include clickable citation metadata (document name, page number, and section header) resolving to active object URLs. |

---

## 6\. Non-Functional Requirements

### 6.1. Security and Privacy

| Requirement ID | Requirement Name | Description |
| :---- | :---- | :---- |
| NFR-1.1 | Central Audit Logging | All system actions—including SQL generations, vector matches, and blocked queries (certified \= false or prompt injection)—must be logged to Cloud Logging. |
| NFR-1.2 | Compliance Adherence & PII masking | Customer payment card numbers, emails, and phone numbers are dynamically masked before reaching LLMs or chat interfaces |

### 6.2. Performance and Scalability

| Requirement ID | Requirement Name | Description |
| :---- | :---- | :---- |
| NFR-2.1 | Conversational Turn Latency | The chat UI must begin streaming responses within 6.0 seconds for single-domain queries (UC-1.x) and within 20.0 seconds for cross-system orchestration (UC-2.x). |
| NFR-2.2 | Serverless Auto-Scaling Scale | The analytical fabric must scale from 0 to 500+ concurrent store manager logins at 9:00 AM without manual warm-ups or persistent idle cluster billing ($0 cluster tax). |

### 6.3. Quality & Accuracy

| Requirement ID | Requirement Name | Description |
| :---- | :---- | :---- |
| NFR-3.1 | SQL Translation Accuracy | Achieve \>=95% accuracy on complex retail analytical benchmark queries |
| NFR-3.2 | Zero Financial Formula Hallucinations |  0% hallucinated financial formulas, strictly adhering to vetted business terms defined in the platform.  |
| NFR-3.3 | Partition Pruning Enforcement | 100% of generated SQL queries against partitioned analytical tables must include active partition filters (e.g., date ranges) to prevent full-table scans. |

### 6.4. Resilience & Error Handling

| Requirement ID | Requirement Name | Description |
| :---- | :---- | :---- |
| NFR-4.1 | Graceful Database Fallback | If a data source is unreachable, return a clean warning ("Regional Store data is currently unreachable") without exposing stack traces or connection strings. |
| NFR-4.2 | Transient Fault Tolerance | Implement exponential backoff retry policies (up to 3 retries) on tool gateways and MCP connectors before declaring connection failure. |
| NFR-4.3 | Orchestrated Partial Synthesis | For cross-system use cases (UC-2.x), if one subagent or tool fails, the Coordinator Router must synthesize a valid partial response, explicitly noting the delayed subsystem. |

---

## 7\. Pilot Implementation Constraints

* Authentication & Sandbox Credentials: Integrations with enterprise SSO (Okta/AD) are excluded. The training sandbox will use functional GCP service accounts, test IAM roles, and mock JWT identity tokens passed in HTTP headers to simulate Store Manager and Auditor personas.  
* Single-Tenant Training Projects: Each learner will deploy their prototype in an isolated Google Cloud project with pre-configured VPC service controls and budget alert notifications.
* All the code will be in a single Github repository that will be used for evaluation.
* Mock Data & Event Generator: Instead of live physical registers, learners will provision an automated POS Event Load Generator in Compute Engine emitting synthetic checkout events to Google Managed Kafka at 0.4 to 10 msg/sec.

---

## 8\. Success and Evaluation Criteria (Rubric)

| Evaluation Category | Success Metric / Criterion | Target / Benchmark | Assessment Method |
| :---- | :---- | :---- | :---- |
| Lakehouse Federation & Egress | Zero-copy in-place query execution against remote S3 Iceberg tables. | 0 Bytes physical replication; 100% query success via REST Catalog. | Inspect job execution plans for federated remote scan operators. |
| Serverless Spark Performance | Elimination of idle cluster costs and successful batch normalization. | 0 Idle DBU/EC2 costs; Spark jobs auto-terminates \<60s post-job. | Audit monitoring metrics for batch lifecycle duration. |
| Real-Time ML scoring Latency | Total latency reported by model endpoint. | \<100ms P95 total latency under pilot load of 500 req/sec. | Audit monitoring metrics |
| RAG Grounding & Citation Accuracy | Precision of troubleshooting steps and clickable citations over PDF manuals. | \>=95% accuracy on benchmark Q\&A; 0% hallucinated warranty rules; 0.7 rejection active. | Evaluate agent responses against 20 golden technical troubleshooting test prompts. |
| Text-to-SQL Translation Accuracy | Execution correctness and adherence to vetted business formulas. | \>=95% syntax/logical correctness; 100% partition pruning filter enforcement. | Run automated SQL validation suite across 30 historical BI test questions. |
| Cross-System Orchestration (UC-2.x) | Successful multi-agent collaboration across SQL, RAG, and streaming cache tools. | 100% Pass on end-to-end multi-domain test scenarios (UC-2.1, UC-2.2, UC-2.3). | Live conversational walkthrough during final presentation. |
| Dynamic PII Masking & Governance | Redaction of customer payment card numbers based on caller IAM token. | 100% Masking (XXXX-XXXX-XXXX-9999) for unauthorized roles; 0 PII leaks. | Test queries using Store Manager token vs. Auditor token and inspect returned payloads. |
| Resilience & Partial Synthesis | System behavior during simulated subsystem outage (e.g., regional DB disconnect). | 100% Graceful degradation; partial synthesis delivered with clear user warning. | Simulate firewall drop on regional DB connector during UC-2.2 execution. |
