class BackendConfig {
  const BackendConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.cloudGatewayUrl,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String cloudGatewayUrl;

  bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
  bool get hasCloudGateway => cloudGatewayUrl.trim().isNotEmpty;

  static const fromEnvironment = BackendConfig(
    supabaseUrl: String.fromEnvironment(
      'LEXPDF_SUPABASE_URL',
      defaultValue: 'https://ibffselezupggrovfruz.supabase.co',
    ),
    supabasePublishableKey: String.fromEnvironment('LEXPDF_SUPABASE_PUBLISHABLE_KEY'),
    cloudGatewayUrl: String.fromEnvironment('LEXPDF_CLOUD_GATEWAY_URL'),
  );
}
