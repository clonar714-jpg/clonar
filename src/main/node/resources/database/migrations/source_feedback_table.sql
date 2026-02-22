-- =============================================================
-- sample-data.sql
-- Seed data for: feedback & source_feedback tables
-- Covers: multihop queries, diverse verticals, ratings,
--         edge cases, and realistic debug_json payloads
-- =============================================================

-- ---------------------------------------------------------------
-- SECTION 1: feedback table
-- Columns: id, session_id, user_id, query, mode, vertical,
--          thumb, reason, comment, debug_json, created_at
-- ---------------------------------------------------------------

INSERT INTO feedback
  (session_id, user_id, query, mode, vertical, thumb, reason, comment, debug_json, created_at)
VALUES

-- 1. Simple factual — thumbs up, no comment
(
  'sess_001', 'user_a1b2',
  'What is the capital of France?',
  'default', 'general',
  'up', NULL, NULL,
  '{"stage":"grounding","confidence":0.98,"hops":1,"latency_ms":312}',
  NOW() - INTERVAL '6 days'
),

-- 2. Multihop reasoning — thumbs up with comment
(
  'sess_002', 'user_c3d4',
  'Which company founded by Elon Musk went public first, Tesla or SpaceX?',
  'default', 'general',
  'up', NULL, 'Great answer, traced the IPO dates clearly.',
  '{"stage":"retrieval_plan","hops":2,"sub_queries":["Tesla IPO date","SpaceX public listing status"],"confidence":0.91,"latency_ms":870}',
  NOW() - INTERVAL '5 days'
),

-- 3. Weather vertical — thumbs up
(
  'sess_003', NULL,
  'Will it rain in Salt Lake City this weekend?',
  'default', 'weather',
  'up', NULL, NULL,
  '{"stage":"grounding","provider":"open-meteo","confidence":0.87,"latency_ms":420}',
  NOW() - INTERVAL '5 days'
),

-- 4. Comparison query — thumbs down, wrong answer reason
(
  'sess_004', 'user_e5f6',
  'Compare the battery life of the MacBook Pro M3 vs Dell XPS 15 2024.',
  'default', 'tech',
  'down', 'wrong_answer', 'The XPS battery hours cited were outdated.',
  '{"stage":"rerank","hops":2,"confidence":0.61,"latency_ms":1100,"sources_used":3}',
  NOW() - INTERVAL '4 days'
),

-- 5. Medical vertical — thumbs down, incomplete answer
(
  'sess_005', 'user_g7h8',
  'What are the side effects of metformin for type 2 diabetes patients over 65?',
  'default', 'medical',
  'down', 'incomplete', 'Missed the renal impairment warnings entirely.',
  '{"stage":"grounding","hops":3,"confidence":0.55,"latency_ms":1540,"fallback_triggered":true}',
  NOW() - INTERVAL '4 days'
),

-- 6. Finance vertical — thumbs up, multihop
(
  'sess_006', 'user_i9j0',
  'How did the Fed rate hikes in 2022-2023 affect 30-year mortgage rates in the US?',
  'default', 'finance',
  'up', NULL, 'Solid sourcing, good timeline.',
  '{"stage":"retrieval_plan_executor","hops":3,"sub_queries":["Fed rate hike 2022","Fed rate hike 2023","30-year mortgage rate trend 2022-2023"],"confidence":0.89,"latency_ms":1350}',
  NOW() - INTERVAL '3 days'
),

-- 7. Edge case — very short query
(
  'sess_007', NULL,
  'Who?',
  'default', 'general',
  'down', 'irrelevant', 'Query was too vague, answer made no sense.',
  '{"stage":"query_rewrite","rewritten_query":null,"confidence":0.12,"latency_ms":95,"error":"ambiguous_query"}',
  NOW() - INTERVAL '3 days'
),

-- 8. Edge case — very long query
(
  'sess_008', 'user_k1l2',
  'Given that the James Webb Space Telescope was launched in December 2021 and began science operations in mid-2022, what are the most significant exoplanet atmospheric discoveries it has made so far, and how do they change our understanding of planetary formation compared to what Hubble found?',
  'default', 'science',
  'up', NULL, 'Extremely detailed and well-cited.',
  '{"stage":"orchestrator","hops":4,"confidence":0.93,"latency_ms":2100,"token_usage":{"prompt":1240,"completion":680}}',
  NOW() - INTERVAL '2 days'
),

-- 9. Legal vertical — thumbs down, hallucination concern
(
  'sess_009', 'user_m3n4',
  'Can an employer in California legally require unpaid overtime for salaried employees?',
  'default', 'legal',
  'down', 'hallucination', 'It cited a law section that does not exist.',
  '{"stage":"grounding","hops":2,"confidence":0.48,"latency_ms":980,"hallucination_flag":true}',
  NOW() - INTERVAL '2 days'
),

-- 10. Multihop chained reasoning — thumbs up
(
  'sess_010', 'user_o5p6',
  'What was the unemployment rate in the US when the last three recessions ended, and which president was in office for each?',
  'default', 'finance',
  'up', NULL, 'Nailed all three recessions with correct dates and presidents.',
  '{"stage":"retrieval_plan_executor","hops":6,"sub_queries":["2001 recession end date","2009 recession end date","2020 recession end date","unemployment rate 2001 recession end","unemployment rate 2009 recession end","unemployment rate 2020 recession end"],"confidence":0.95,"latency_ms":2400}',
  NOW() - INTERVAL '1 day'
),

-- 11. Edge case — non-English query
(
  'sess_011', NULL,
  '¿Cuál es la diferencia entre inteligencia artificial y machine learning?',
  'default', 'tech',
  'up', NULL, NULL,
  '{"stage":"query_rewrite","detected_lang":"es","rewritten_query":"What is the difference between artificial intelligence and machine learning?","confidence":0.88,"latency_ms":310}',
  NOW() - INTERVAL '1 day'
),

-- 12. Edge case — code/programming query
(
  'sess_012', 'user_q7r8',
  'In TypeScript, what is the difference between unknown and any, and when should I use each?',
  'default', 'tech',
  'up', NULL, 'Clear examples, exactly what I needed.',
  '{"stage":"grounding","hops":1,"confidence":0.97,"latency_ms":280,"source_type":"documentation"}',
  NOW() - INTERVAL '12 hours'
),

-- 13. Ambiguous query — thumbs down
(
  'sess_013', 'user_s9t0',
  'Is it worth it?',
  'default', 'general',
  'down', 'irrelevant', 'Could not understand the question context at all.',
  '{"stage":"query_rewrite","rewritten_query":null,"confidence":0.08,"latency_ms":88,"error":"ambiguous_query"}',
  NOW() - INTERVAL '10 hours'
),

-- 14. Streaming mode — thumbs up
(
  'sess_014', 'user_u1v2',
  'Summarize the key arguments for and against universal basic income.',
  'stream', 'general',
  'up', NULL, 'Good balanced summary.',
  '{"stage":"orchestrator_stream","hops":2,"confidence":0.86,"latency_ms":1800,"stream_chunks":14}',
  NOW() - INTERVAL '8 hours'
),

-- 15. Edge case — numeric/math query
(
  'sess_015', NULL,
  'If I invest $500 per month at 7% annual return for 30 years, how much will I have?',
  'default', 'finance',
  'up', NULL, NULL,
  '{"stage":"grounding","hops":1,"confidence":0.99,"latency_ms":195,"computation":true}',
  NOW() - INTERVAL '4 hours'
);


-- ---------------------------------------------------------------
-- SECTION 2: source_feedback table
-- Columns: id, session_id, source_index, url, reason, user_id, created_at
-- ---------------------------------------------------------------

INSERT INTO source_feedback
  (session_id, source_index, url, reason, user_id, created_at)
VALUES

-- Reported sources for session_004 (comparison query with bad data)
(
  'sess_004', 0,
  'https://example-tech-review.com/dell-xps-15-2023-review',
  'outdated_info',
  'user_e5f6',
  NOW() - INTERVAL '4 days'
),
(
  'sess_004', 1,
  'https://example-laptop-specs.com/xps15-battery',
  'wrong_data',
  'user_e5f6',
  NOW() - INTERVAL '4 days'
),

-- Reported source for session_005 (medical — missing renal warnings)
(
  'sess_005', 2,
  'https://example-health-site.com/metformin-overview',
  'incomplete_information',
  'user_g7h8',
  NOW() - INTERVAL '4 days'
),

-- Reported source for session_009 (legal hallucination)
(
  'sess_009', 0,
  'https://example-legal-db.com/ca-labor-code-510b',
  'hallucination',
  'user_m3n4',
  NOW() - INTERVAL '2 days'
),
(
  'sess_009', 1,
  'https://example-law-review.com/ca-overtime-rules',
  'misleading',
  'user_m3n4',
  NOW() - INTERVAL '2 days'
),

-- Positive signal — source NOT reported (session_010 multihop, no reports)
-- (no rows = implicit positive signal for those sources)

-- Reported source for session_013 (ambiguous query)
(
  'sess_013', 0,
  'https://example-generic-site.com/is-it-worth-it',
  'irrelevant',
  'user_s9t0',
  NOW() - INTERVAL '10 hours'
),

-- Edge case — anonymous user reports a source
(
  'sess_003', 1,
  'https://example-weather-aggregator.com/slc-weekend-forecast',
  'outdated_info',
  NULL,
  NOW() - INTERVAL '5 days'
),

-- Multihop query source report — one source wrong out of many
(
  'sess_002', 3,
  'https://example-finance-news.com/tesla-ipo-2010',
  'wrong_data',
  'user_c3d4',
  NOW() - INTERVAL '5 days'
);



