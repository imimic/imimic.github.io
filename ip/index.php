<?php 
$ip_info = isset($_SERVER['HTTP_IP']) ? $_SERVER['HTTP_IP'] : 'Unknown';
$ip_city = isset($_SERVER['HTTP_IP_CITY']) ? $_SERVER['HTTP_IP_CITY'] : 'Unknown';
$ip_asn = isset($_SERVER['HTTP_IP_ASN']) ? $_SERVER['HTTP_IP_ASN'] : 'Unknown';
$ip_country = isset($_SERVER['HTTP_IP_COUNTRY']) ? $_SERVER['HTTP_IP_COUNTRY'] : '';
$ip_http = isset($_SERVER['HTTP_IP_HTTP']) ? $_SERVER['HTTP_IP_HTTP'] : 'Unknown';
$ip_lat = isset($_SERVER['HTTP_IP_LAT']) ? $_SERVER['HTTP_IP_LAT'] : 'Unknown';
$ip_lon = isset($_SERVER['HTTP_IP_LON']) ? $_SERVER['HTTP_IP_LON'] : 'Unknown';
$ip_threat = isset($_SERVER['HTTP_IP_THREAT']) ? $_SERVER['HTTP_IP_THREAT'] : 'Unknown';
$ip_time = isset($_SERVER['HTTP_IP_TIME']) ? $_SERVER['HTTP_IP_TIME'] : 'Unknown';
$ip_ua = isset($_SERVER['HTTP_IP_UA']) ? $_SERVER['HTTP_IP_UA'] : 'Unknown';
$isp_info = unserialize(file_get_contents(sprintf('http://ip-api.com/php/%s?fields=hosting,currency,country,isp', $ip_info)));
$ip_isp = isset($isp_info['isp']) ? $isp_info['isp'] : 'Unknown';
$ip_type = ($isp_info['hosting']) ? "DataCenter" : "Residential/Cellular";
$ip_country_name = isset($isp_info['country']) ? $isp_info['country'] : '';
$ip_currency = isset($isp_info['currency']) ? $isp_info['currency'] : '';
$rdns = gethostbyaddr($ip_info);
$ip_host = ($rdns == $ip_info || $rdns == "") ? "None" : $rdns;
$cf_colo = isset($_SERVER['HTTP_CF_RAY']) ? substr($_SERVER['HTTP_CF_RAY'], -3) : 'Unknown';
?>

<!DOCTYPE html>
<html>
<head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>MyIP</title>
<link rel="stylesheet" href="/ip/style.css">
<script async src="https://lvlv.lv/umami/script.js" data-website-id="8c6f1f0c-d6b3-44d0-b4f5-badfb366a181"></script>
</head>
<body>
<div class="container">
<h1>My IP Address</h1>
<table>
<tr><th>Public IP</th><td><?php echo $ip_info; ?></td></tr>
<tr><th>Hostname</th><td><?php echo $ip_host; ?></td></tr>
<tr><th>IP Type</th><td><?php echo $ip_type; ?></td></tr>
<tr><th>Location</th><td><?php echo $ip_city . ', ' . $ip_country_name; ?></td></tr>
<tr><th>ASN/ISP</th><td><?php echo 'AS' . $ip_asn . ' ' . $ip_isp; ?></td></tr>
<tr><th>Coordinate</th><td><?php echo $ip_lon . ', ' . $ip_lat; ?></td></tr>
<tr><th>TZ/CCY</th><td><?php echo $ip_time . ' (' . $ip_country . ')' . ' ' . $ip_currency; ?></td></tr>
<tr><th>Protocol</th><td><?php echo $ip_http; ?></td></tr>
<tr><th>Cloudflare</th><td><?php echo 'Colo: ' . $cf_colo . ' | Threat: ' . $ip_threat; ?></td></tr>
<tr><th>UserAgent</th><td><?php echo $ip_ua; ?></td></tr>
</table>
</div>
<div class="footer">
<p>&copy; 2024 <a href="https://lvlv.lv">Midori</a>. All Rights Reserved.</p>
</div>
</body>
</html>
