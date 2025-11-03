#!/bin/ash
echo "⏳ Starting PHP-FPM..."
if /usr/sbin/php-fpm8 --fpm-config /home/container/php-fpm/php-fpm.conf --daemonize; then
    echo "✅ PHP-FPM started successfully."
else
    echo "❌ Failed to start PHP-FPM."
    exit 1
fi

echo "⏳ Starting Nginx..."
/usr/sbin/nginx -c /home/container/nginx/nginx.conf -p /home/container/

echo "✅ Web server started successfully."

tail -f /dev/null