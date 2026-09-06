class BackendConfig {
  const BackendConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.cloudGatewayUrl,
    required this.aiGatewayUrl,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String cloudGatewayUrl;
  final String aiGatewayUrl;

  bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
  bool get hasCloudGateway => cloudGatewayUrl.trim().isNotEmpty;
  bool get hasAiGateway => aiGatewayUrl.trim().isNotEmpty;

  static const fromEnvironment = BackendConfig(
    supabaseUrl: String.fromEnvironment(
      'LEXPDF_SUPABASE_URL',
      defaultValue: 'https://ibffselezupggrovfruz.supabase.co',
    ),
    supabasePublishableKey: String.fromEnvironment('LEXPDF_SUPABASE_PUBLISHABLE_KEY'),
    cloudGatewayUrl: String.fromEnvironment('LEXPDF_CLOUD_GATEWAY_URL'),
    aiGatewayUrl: String.fromEnvironment('LEXPDF_AI_GATEWAY_URL'),
  );
}
