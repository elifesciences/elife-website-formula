<?php

use eLife\Monolog\eLifeJsonFormatter;
use Monolog\Handler\StreamHandler;
use Monolog\Processor\GitProcessor;
use Monolog\Processor\MemoryPeakUsageProcessor;
use Monolog\Processor\MemoryUsageProcessor;

$databases = [
  'default' =>
    [
      'default' =>
        [
          'database' => '{{ pillar.elife_website.db.name }}',
          'username' => '{{ pillar.elife.db_root.username }}',
          'password' => '{{ pillar.elife.db_root.password }}',
          'host' => 'localhost',
          'port' => '',
          'driver' => 'mysql',
          'prefix' => '',
        ],
    ],
];

$conf['redis_client_host'] = '{{ pillar.elife.redis.host }}';
$conf['redis_client_port'] = {{ pillar.elife.redis.port }};
$conf['redis_client_base'] = 0;

{% if pillar.elife.env == "dev" %}
$conf['elife_environment'] = ELIFE_ENVIRONMENT_DEVELOPMENT;
{% else %}
$conf['elife_environment'] = ELIFE_ENVIRONMENT_PRODUCTION;
{% endif %}

{% if pillar.elife.env == "end2end" %}
$conf['elife_article_source_assets_base_path'] = 'http://end2end-elife-published.s3.amazonaws.com/articles/';
{% elif pillar.elife.env == "continuumtest" %}
$conf['elife_article_source_assets_base_path'] = 'http://ct-elife-publishing-cdn.s3.amazonaws.com/';
{% endif %}

$conf['imagemagick_convert'] = '/usr/bin/convert';

$conf['elife_node_binary'] = 'nodejs';

$conf['elife_monolog_handlers'] = $stream_handler = new StreamHandler('{{ pillar.elife_website.logfile }}');
$stream_handler
  ->setFormatter(new eLifeJsonFormatter('{{ grains['fqdn'] }}'))
  ->pushProcessor(new GitProcessor())
  ->pushProcessor(new MemoryUsageProcessor())
  ->pushProcessor(new MemoryPeakUsageProcessor());
